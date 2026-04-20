(in-package #:photo-ai-lisp)

;;; Combined acceptor: WebSocket dispatch + easy-handler dispatch table.
;;; hunchensocket:websocket-acceptor specializes on websocket upgrade requests
;;; and calls call-next-method for plain HTTP, which lands in
;;; hunchentoot:easy-acceptor and its *dispatch-table* loop.
(defclass ws-easy-acceptor (hunchensocket:websocket-acceptor
                             hunchentoot:easy-acceptor)
  ()
  (:documentation "Acceptor that handles both WebSocket upgrades and HTTP easy-handlers."))

;;; Echo WebSocket resource.
;;; Every text or binary message is echoed verbatim to the sender.

(defclass echo-resource (hunchensocket:websocket-resource)
  ()
  (:default-initargs :client-class 'hunchensocket:websocket-client))

(defvar *echo-resource* (make-instance 'echo-resource))

(defmethod hunchensocket:text-message-received ((resource echo-resource)
                                                 (client   hunchensocket:websocket-client)
                                                 message)
  (hunchensocket:send-text-message client message))

(defun %find-echo-resource (request)
  (when (string= "/ws/echo" (hunchentoot:script-name request))
    *echo-resource*))

;;; Shell WebSocket resource — tasks 2b/2c/2d.
;;; Each client connection owns one child-process (from proc.lisp).
;;; 2b: stdin write  2c: stdout pump thread  2d: graceful shutdown

(defclass shell-client (hunchensocket:websocket-client)
  ((child        :initform nil :accessor shell-client-child)
   (reader-thread :initform nil :accessor shell-client-reader-thread)))

(defclass shell-resource (hunchensocket:websocket-resource)
  ()
  (:default-initargs :client-class 'shell-client))

(defvar *shell-resource* (make-instance 'shell-resource))

;;; Registry of currently connected /ws/shell clients so /api/inject can
;;; broadcast text to every attached session's child stdin. This is the
;;; minimal equivalent of the Rust-version CP protocol's session fan-out.
(defvar *shell-clients* '())
(defvar *shell-clients-lock* (bordeaux-threads:make-lock "shell-clients"))

(defun %register-shell-client (client)
  (bordeaux-threads:with-lock-held (*shell-clients-lock*)
    (pushnew client *shell-clients*)))

(defun %unregister-shell-client (client)
  (bordeaux-threads:with-lock-held (*shell-clients-lock*)
    (setf *shell-clients* (remove client *shell-clients*))))

(defun shell-broadcast-input (text)
  "Write TEXT to the child stdin of every connected shell client.
   Returns the number of clients reached. TEXT is recorded in the
   trace ring as :in (dir) for observability."
  (let ((recipients (bordeaux-threads:with-lock-held (*shell-clients-lock*)
                      (copy-list *shell-clients*))))
    (shell-trace-record :in text)
    (loop for c in recipients
          for child = (shell-client-child c)
          when child
            count (handler-case
                      (progn
                        (write-string text (child-process-stdin child))
                        (finish-output (child-process-stdin child))
                        t)
                    (error () nil)))))

(defun inject-handler (text)
  "HTTP handler body for GET /api/inject?text=... Returns
     {\"ok\":true,\"recipients\":N,\"bytes\":M}
   N = number of /ws/shell sessions that received the text."
  (let* ((t0 (or text ""))
         (n (shell-broadcast-input t0)))
    (format nil "{\"ok\":true,\"recipients\":~a,\"bytes\":~a}" n (length t0))))

;;; Observability: trace bytes flowing through /ws/shell.
;;; Entries are plists: (:ts <iso-string> :dir :in|:out :bytes N :preview "...")
;;; :in  = browser -> /ws/shell -> child stdin
;;; :out = child stdout -> /ws/shell -> browser
;;; Ring buffer, oldest entries dropped. Exposed via /api/shell-trace so a
;;; test or a human can curl to verify that a preset click actually reached
;;; the child process, without parsing server logs.
(defvar *shell-trace-max* 100)
(defvar *shell-trace* '())
(defvar *shell-trace-lock* (bordeaux-threads:make-lock "shell-trace"))

(defun %iso-now ()
  (multiple-value-bind (s m h d mo y) (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0dZ" y mo d h m s)))

(defun %preview (s)
  (let* ((s (or s ""))
         (n (min 80 (length s))))
    (map 'string (lambda (c)
                   (cond ((char= c #\Return) #\space)
                         ((char= c #\Newline) #\space)
                         ((< (char-code c) 32) #\.)
                         (t c)))
         (subseq s 0 n))))

(defun shell-trace-record (dir message)
  "Append one trace entry. DIR is :in or :out. MESSAGE is the string."
  (bordeaux-threads:with-lock-held (*shell-trace-lock*)
    (push (list :ts (%iso-now)
                :dir dir
                :bytes (length message)
                :preview (%preview message))
          *shell-trace*)
    (when (> (length *shell-trace*) *shell-trace-max*)
      (setf *shell-trace* (subseq *shell-trace* 0 *shell-trace-max*)))))

(defun shell-trace-snapshot ()
  "Return a copy of the trace (newest first). Thread-safe."
  (bordeaux-threads:with-lock-held (*shell-trace-lock*)
    (copy-list *shell-trace*)))

(defun shell-trace-clear ()
  "Reset the trace. Useful in tests."
  (bordeaux-threads:with-lock-held (*shell-trace-lock*)
    (setf *shell-trace* '())))

(defun shell-trace-handler ()
  "HTTP handler body for GET /api/shell-trace. Returns a JSON array
   of trace entries, newest first."
  (let ((entries (shell-trace-snapshot)))
    (format nil "[~{~a~^,~}]"
            (loop for e in entries
                  collect (format nil
                                  "{\"ts\":\"~a\",\"dir\":\"~a\",\"bytes\":~a,\"preview\":\"~a\"}"
                                  (getf e :ts)
                                  (string-downcase (symbol-name (getf e :dir)))
                                  (getf e :bytes)
                                  (%json-escape (getf e :preview)))))))

(defun %shell-argv ()
  (if (uiop:os-windows-p)
      '("cmd.exe")
      (list "/bin/bash" "--norc" "--noprofile")))

(defun %scrub-for-utf8 (s)
  "Replace lone UTF-16 surrogates (#xD800–#xDFFF) and NIL/undefined
   chars with U+FFFD. cmd.exe on Windows can emit bytes that decode
   to surrogates under the default flexi-streams/hunchentoot setup,
   which then blow up hunchensocket's UTF-8 text-frame encoder with
   'NIL is not of type (MOD 1114112)'."
  (let ((out (make-array (length s) :element-type 'character
                                    :adjustable t :fill-pointer 0)))
    (loop for c across s
          for code = (and c (char-code c))
          do (vector-push-extend
              (cond
                ((null code) #\?)
                ((<= #xD800 code #xDFFF) #\?)
                ((> code #x10FFFF) #\?)
                (t c))
              out))
    (coerce out 'simple-string)))

;;; 2c — stdout pump: read chunks from child stdout, push to websocket.
(defun %stdout-pump (client child)
  (let ((out (child-process-stdout child))
        (buf (make-array 512 :element-type 'character
                             :adjustable t :fill-pointer 0)))
    (handler-case
        (loop
          (cond
            ((listen out)
             (handler-case
                 (let ((c (read-char out nil :eof)))
                   (cond
                     ((eq c :eof) (return))
                     ((null c) nil)   ; defensive: some streams return NIL
                     (t (vector-push-extend c buf))))
               (error () nil)))
            ((plusp (length buf))
             (let ((chunk (%scrub-for-utf8 (copy-seq buf))))
               (shell-trace-record :out chunk)
               (handler-case
                   (hunchensocket:send-text-message client chunk)
                 (error (e)
                   (format *error-output* "PUMP-SEND-ERR type=~a msg=~a chars=~a~%"
                           (type-of e) e
                           (map 'list #'char-code (subseq chunk 0 (min 20 (length chunk)))))
                   (finish-output *error-output*))))
             (setf (fill-pointer buf) 0))
            ((not (child-alive-p child))
             (return))
            (t (sleep 0.02))))
      (error () nil))))

(defun %agent-picker-command ()
  "Relative invocation of the platform-appropriate agent picker script.
   Path is relative to the server's cwd (the repo root when launched via
   scripts/demo.sh)."
  (if (uiop:os-windows-p)
      "scripts\\pick-agent.cmd"
      "sh scripts/pick-agent.sh"))

(defvar *auto-pick-agent*
  (not (equal (uiop:getenv "DISABLE_AGENT_PICKER") "1"))
  "When true, /ws/shell clients get the agent picker auto-injected on
   connect. Flip to NIL or set DISABLE_AGENT_PICKER=1 to skip.")

;;; 2b — on connect: spawn child, start stdout pump thread.
(defmethod hunchensocket:client-connected ((resource shell-resource)
                                            (client   shell-client))
  (handler-case
      (let ((child (spawn-child (%shell-argv))))
        (setf (shell-client-child client) child)
        (setf (shell-client-reader-thread client)
              (bordeaux-threads:make-thread
               (lambda () (%stdout-pump client child))
               :name "shell-stdout-pump"))
        (%register-shell-client client)
        ;; Auto-inject the agent picker after the shell banner settles.
        (when *auto-pick-agent*
          (bordeaux-threads:make-thread
           (lambda ()
             (sleep 0.4)
             (ignore-errors
               (let ((stdin (child-process-stdin child))
                     (line  (format nil "~a~c~c"
                                    (%agent-picker-command)
                                    #\Return #\Newline)))
                 (write-string line stdin)
                 (finish-output stdin))))
           :name "agent-picker-inject")))
    (error (e)
      (ignore-errors
        (hunchensocket:send-text-message
         client (format nil "[failed to start shell: ~a]" e))))))

;;; 2d — graceful shutdown: close stdin, wait up to 2s, then terminate.
(defmethod hunchensocket:client-disconnected ((resource shell-resource)
                                               (client   shell-client))
  (%unregister-shell-client client)
  (let ((child (shell-client-child client)))
    (when child
      (kill-child child)
      (setf (shell-client-child client) nil))))

;;; 2b — text message received: write to child stdin.
(defmethod hunchensocket:text-message-received ((resource shell-resource)
                                                  (client   shell-client)
                                                  message)
  (shell-trace-record :in message)
  (let ((child (shell-client-child client)))
    (when child
      (ignore-errors
        (write-string message (child-process-stdin child))
        (finish-output (child-process-stdin child))))))

(defun %find-shell-resource (request)
  (when (string= "/ws/shell" (hunchentoot:script-name request))
    *shell-resource*))

(pushnew '%find-echo-resource hunchensocket:*websocket-dispatch-table*)
(pushnew '%find-shell-resource hunchensocket:*websocket-dispatch-table*)

;;; /term — xterm.js page connecting to /ws/echo (Phase 1 echo demo).
;;; /shell — xterm.js page connecting to /ws/shell (Phase 2 subprocess).

(hunchentoot:define-easy-handler (shell-page :uri "/shell") ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  "<!DOCTYPE html>
<html>
<head>
  <meta charset=\"utf-8\">
  <title>shell</title>
  <style>
    html, body { background: #1e1e1e; margin: 0; padding: 0; height: 100%; }
    #terminal { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div id=\"terminal\"></div>
  <script type=\"module\">
    // Renderer: ghostty-web WASM bundle served from /vendor/ by the Lisp hub.
    // PTY lives on the Lisp side at /ws/shell. Keep the protocol dumb so
    // /api/inject and the picker auto-inject (term.lisp client-connected)
    // both continue to reach this PTY without a separate node daemon.
    import { init, Terminal, FitAddon } from '/vendor/ghostty-web.js';
    await init();

    const term = new Terminal({
      cols: 80, rows: 24,
      fontFamily: 'JetBrains Mono, Consolas, monospace',
      fontSize: 14,
      theme: { background: '#1e1e1e', foreground: '#d4d4d4' },
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    const container = document.getElementById('terminal');
    await term.open(container);
    fit.fit();
    fit.observeResize();
    // Ghostty-web renders into a canvas; without explicit focus the iframe
    // swallows keystrokes. Re-grab focus on any pointer event so clicking
    // anywhere in the terminal area always routes keys to the PTY.
    term.focus();
    container.addEventListener('pointerdown', () => term.focus());
    window.addEventListener('focus', () => term.focus());

    let ws = null, reconnectDelay = 500;
    function connect() {
      ws = new WebSocket('ws://' + location.host + '/ws/shell');
      ws.onopen = () => { reconnectDelay = 500; };
      ws.onmessage = (e) => { term.write(e.data); };
      ws.onclose = () => {
        term.write('\\r\\n\\x1b[31m[disconnected — retrying]\\x1b[0m\\r\\n');
        setTimeout(connect, reconnectDelay);
        reconnectDelay = Math.min(reconnectDelay * 2, 5000);
      };
      ws.onerror = () => { term.write('\\r\\n\\x1b[31m[ws error]\\x1b[0m\\r\\n'); };
    }
    connect();

    term.onData((data) => {
      if (ws && ws.readyState === WebSocket.OPEN) ws.send(data);
    });

    // Legacy: parent pages can still postMessage inject text directly.
    // The primary path is /api/inject (Lisp broadcasts to every /ws/shell),
    // but keeping this lets hot-swapped UIs talk to us without a fetch round-trip.
    window.addEventListener('message', (ev) => {
      const m = ev.data;
      if (!m || m.type !== 'inject' || typeof m.data !== 'string') return;
      if (!ws || ws.readyState !== WebSocket.OPEN) return;
      ws.send(m.data);
    });
  </script>
</body>
</html>")

(hunchentoot:define-easy-handler (term-page :uri "/term") ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  "<!DOCTYPE html>
<html>
<head>
  <meta charset=\"utf-8\">
  <title>terminal echo</title>
  <link rel=\"stylesheet\" href=\"https://unpkg.com/xterm@5.3.0/css/xterm.css\" />
  <style>
    html, body { background: #1e1e1e; margin: 0; padding: 0; height: 100%; }
    #terminal { padding: 8px; }
  </style>
</head>
<body>
  <div id=\"terminal\"></div>
  <script src=\"https://unpkg.com/xterm@5.3.0/lib/xterm.js\"></script>
  <script>
    const term = new Terminal({
      cursorBlink: true,
      fontFamily: 'Menlo, Consolas, monospace',
      fontSize: 14,
      theme: { background: '#1e1e1e' }
    });
    term.open(document.getElementById('terminal'));

    const ws = new WebSocket('ws://' + location.host + '/ws/echo');
    ws.binaryType = 'arraybuffer';

    ws.onopen = function() {
      term.write('\\r\\n\\x1b[32mConnected to echo server\\x1b[0m\\r\\n');
      term.write('Type anything — keystrokes are echoed back verbatim.\\r\\n\\r\\n');
    };
    ws.onclose = function() {
      term.write('\\r\\n\\x1b[31m[disconnected]\\x1b[0m\\r\\n');
    };
    ws.onerror = function(e) {
      term.write('\\r\\n\\x1b[31m[ws error]\\x1b[0m\\r\\n');
    };
    ws.onmessage = function(e) {
      if (typeof e.data === 'string') {
        term.write(e.data);
      } else {
        term.write(new Uint8Array(e.data));
      }
    };

    term.onData(function(data) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(data);
      }
    });
  </script>
</body>
</html>")
