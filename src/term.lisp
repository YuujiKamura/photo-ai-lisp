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

(defun %shell-argv ()
  (if (uiop:os-windows-p)
      '("cmd.exe")
      (list "/bin/bash" "--norc" "--noprofile")))

;;; 2c — stdout pump: read chunks from child stdout, push to websocket.
(defun %stdout-pump (client child)
  (let ((out (child-process-stdout child))
        (buf (make-array 512 :element-type 'character
                             :adjustable t :fill-pointer 0)))
    (handler-case
        (loop
          (cond
            ((listen out)
             (let ((c (read-char out nil :eof)))
               (if (eq c :eof)
                   (return)
                   (vector-push-extend c buf))))
            ((plusp (length buf))
             (ignore-errors
               (hunchensocket:send-text-message client (copy-seq buf)))
             (setf (fill-pointer buf) 0))
            ((not (child-alive-p child))
             (return))
            (t (sleep 0.02))))
      (error () nil))))

;;; 2b — on connect: spawn child, start stdout pump thread.
(defmethod hunchensocket:client-connected ((resource shell-resource)
                                            (client   shell-client))
  (handler-case
      (let ((child (spawn-child (%shell-argv))))
        (setf (shell-client-child client) child)
        (setf (shell-client-reader-thread client)
              (bordeaux-threads:make-thread
               (lambda () (%stdout-pump client child))
               :name "shell-stdout-pump")))
    (error (e)
      (ignore-errors
        (hunchensocket:send-text-message
         client (format nil "[failed to start shell: ~a]" e))))))

;;; 2d — graceful shutdown: close stdin, wait up to 2s, then terminate.
(defmethod hunchensocket:client-disconnected ((resource shell-resource)
                                               (client   shell-client))
  (let ((child (shell-client-child client)))
    (when child
      (kill-child child)
      (setf (shell-client-child client) nil))))

;;; 2b — text message received: write to child stdin.
(defmethod hunchensocket:text-message-received ((resource shell-resource)
                                                  (client   shell-client)
                                                  message)
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
    term.write('\\x1b[33m[connecting to shell subprocess...]\\x1b[0m\\r\\n');

    const ws = new WebSocket('ws://' + location.host + '/ws/shell');
    ws.binaryType = 'arraybuffer';

    ws.onopen  = function() { term.write('\\x1b[32m[connected]\\x1b[0m\\r\\n'); };
    ws.onclose = function() { term.write('\\r\\n\\x1b[31m[disconnected]\\x1b[0m\\r\\n'); };
    ws.onerror = function() { term.write('\\r\\n\\x1b[31m[ws error]\\x1b[0m\\r\\n'); };
    ws.onmessage = function(e) {
      term.write(typeof e.data === 'string' ? e.data : new Uint8Array(e.data));
    };

    term.onData(function(data) {
      if (ws.readyState === WebSocket.OPEN) ws.send(data);
    });

    // Accept postMessage from the parent window (the main UI) to inject
    // text into the shell. Expected shape: {type:'inject', data:'...'}.
    window.addEventListener('message', function(ev) {
      var msg = ev.data;
      if (!msg || msg.type !== 'inject' || typeof msg.data !== 'string') return;
      if (ws.readyState !== WebSocket.OPEN) return;
      ws.send(msg.data);
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
