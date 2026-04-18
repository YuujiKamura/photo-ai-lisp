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
  ;; cmd.exe /Q suppresses echo; we keep echo off for pipe-driven usage so the
  ;; terminal does not double-print characters we already typed. The banner
  ;; still appears once at startup.
  (if (uiop:os-windows-p)
      '("cmd.exe" "/Q")
      (list "/bin/bash" "--norc" "--noprofile")))

;;; 2c — stdout pump: read chunks from child stdout, push to websocket.
;;; LISTEN can lie about character availability on Windows pipe streams (and on
;;; UTF-8 decoded streams mid-multibyte), so READ-CHAR may return NIL even when
;;; we were told a character was ready. Treat NIL as "no data right now" —
;;; flushing the buffer and sleeping briefly — rather than trying to push NIL
;;; into the character buffer, which used to signal "(MOD 1114112)" type
;;; errors and tear down the WebSocket client on the first keystroke.
(defun %stdout-pump (client child)
  (let ((out (child-process-stdout child))
        (buf (make-array 512 :element-type 'character
                             :adjustable t :fill-pointer 0)))
    (handler-case
        (loop
          (cond
            ((listen out)
             (let ((c (read-char out nil :eof)))
               (cond
                 ((eq c :eof) (return))
                 ((null c)
                  ;; LISTEN said yes but READ-CHAR had nothing. Flush any
                  ;; pending buffer and back off.
                  (when (plusp (length buf))
                    (ignore-errors
                      (hunchensocket:send-text-message client (copy-seq buf)))
                    (setf (fill-pointer buf) 0))
                  (sleep 0.02))
                 (t (vector-push-extend c buf)))))
            ((plusp (length buf))
             (ignore-errors
               (hunchensocket:send-text-message client (copy-seq buf)))
             (setf (fill-pointer buf) 0))
            ((not (child-alive-p child))
             (return))
            (t (sleep 0.02))))
      (error (e)
        (format *error-output*
                "[shell stdout-pump] ~a: ~a~%"
                (type-of e) e)))))

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

;;; Accept binary frames on the shell resource — hunchensocket's default
;;; CHECK-MESSAGE rejects them. We need binary frames because hunchensocket's
;;; text-frame path UTF-8-decodes the masked payload through flexi-streams,
;;; which signals "(MOD 1114112)" for payloads ending in a bare CR (0x0D)
;;; under :crlf line-ending handling. xterm.js' Enter key emits exactly that,
;;; which kills the WebSocket on the first keystroke.
(defmethod hunchensocket:check-message ((resource shell-resource)
                                         (client hunchensocket:websocket-client)
                                         (opcode (eql hunchensocket::+binary-frame+))
                                         length total)
  (declare (ignore resource client length total))
  nil)

(defun %write-octets-to-child (octets child)
  ;; cmd.exe reading from a pipe completes a line on #\Newline (LF), not on
  ;; bare CR. xterm.js's Enter key emits #\Return only, so translate bare CR
  ;; (not already followed by LF) into CRLF before handing it to the child.
  (let ((stdin (child-process-stdin child))
        (n (length octets))
        (i 0))
    (loop while (< i n)
          for o = (aref octets i)
          do (cond
               ((= o 13)                    ; CR
                (write-char #\Return stdin)
                (write-char #\Newline stdin)
                ;; If the client already sent CRLF, skip the LF.
                (when (and (< (1+ i) n) (= (aref octets (1+ i)) 10))
                  (incf i))
                (incf i))
               (t (write-char (code-char o) stdin) (incf i))))
    (finish-output stdin)))

;;; 2b — binary message received: write raw bytes to child stdin.
(defmethod hunchensocket:binary-message-received ((resource shell-resource)
                                                   (client   shell-client)
                                                   message)
  (let ((child (shell-client-child client)))
    (when (and child (child-alive-p child))
      (handler-case (%write-octets-to-child message child)
        (error (e)
          (format *error-output* "[shell binary-message-received] ~a~%" e))))))

;;; 2b — text message received: write to child stdin. Kept as a fallback for
;;; clients that don't send binary frames (and for simple payloads without
;;; trailing CR where the flexi-streams path actually works).
(defmethod hunchensocket:text-message-received ((resource shell-resource)
                                                  (client   shell-client)
                                                  message)
  (let ((child (shell-client-child client)))
    (when (and child (child-alive-p child))
      (handler-case
          (progn
            (write-string message (child-process-stdin child))
            (finish-output (child-process-stdin child)))
        (error (e)
          (format *error-output* "[shell text-message-received] ~a~%" e))))))

(defun %find-shell-resource (request)
  (when (string= "/ws/shell" (hunchentoot:script-name request))
    *shell-resource*))

(pushnew '%find-echo-resource hunchensocket:*websocket-dispatch-table*)
(pushnew '%find-shell-resource hunchensocket:*websocket-dispatch-table*)

;;; /static/* — serve the ghostty-web bundle (and any future assets) from
;;; the repo's static/ directory. ghostty-web is an ES module that loads
;;; ghostty-vt.wasm at runtime, so both files must sit under the same
;;; URL prefix the browser sees.
(defun %static-root ()
  (merge-pathnames
   "static/"
   (or (asdf:system-source-directory :photo-ai-lisp)
       *default-pathname-defaults*)))

(pushnew (hunchentoot:create-folder-dispatcher-and-handler
          "/static/" (%static-root))
         hunchentoot:*dispatch-table*
         :test #'equal)

;;; /term — ghostty-web page connecting to /ws/echo (Phase 1 echo demo).
;;; /shell — ghostty-web page connecting to /ws/shell (Phase 2 subprocess).

(hunchentoot:define-easy-handler (shell-page :uri "/shell") ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  "<!DOCTYPE html>
<html>
<head>
  <meta charset=\"utf-8\">
  <title>shell</title>
  <style>
    html, body { background: #1e1e1e; color: #eee; margin: 0; padding: 0; height: 100%;
                 font-family: Menlo, Consolas, monospace; }
    #terminal { padding: 8px; height: calc(100vh - 16px); }
    #status { position: fixed; top: 4px; right: 8px; font-size: 11px; opacity: 0.6; }
  </style>
</head>
<body>
  <div id=\"status\">connecting…</div>
  <div id=\"terminal\"></div>
  <script type=\"module\">
    import { init, Terminal } from '/static/ghostty-web/ghostty-web.js';

    const statusEl = document.getElementById('status');
    function setStatus(s) { statusEl.textContent = s; }

    await init();

    const term = new Terminal({
      cols: 100, rows: 30,
      theme: { background: '#1e1e1e', foreground: '#eeeeee' }
    });
    term.open(document.getElementById('terminal'));

    // Expose the Terminal instance for the headless-browser smoke in
    // demo/shell-smoke.mjs — ghostty-web renders to <canvas>, so the only
    // reliable way to read what's on screen is through the buffer API.
    window.__ghosttyTerm = term;

    const wsProto = location.protocol === 'https:' ? 'wss' : 'ws';
    const ws = new WebSocket(wsProto + '://' + location.host + '/ws/shell');
    ws.binaryType = 'arraybuffer';

    ws.onopen  = () => setStatus('connected');
    ws.onclose = () => setStatus('disconnected');
    ws.onerror = () => setStatus('ws error');
    ws.onmessage = (e) => {
      term.write(typeof e.data === 'string' ? e.data : new Uint8Array(e.data));
    };

    const encoder = new TextEncoder();
    term.onData((data) => {
      if (ws.readyState === WebSocket.OPEN) {
        // Binary frame — hunchensocket's text-frame decode path mishandles
        // bare CR (\\r) in :crlf mode and 1011-closes the socket.
        ws.send(encoder.encode(data));
      }
    });

    term.onResize(({ cols, rows }) => {
      // Server-side PTY resize is not wired yet; send as JSON sentinel so
      // the Lisp side can pick it up later without breaking byte stream.
      if (ws.readyState === WebSocket.OPEN) {
        ws.send('\\x1bGW:resize:' + cols + 'x' + rows);
      }
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
  <style>
    html, body { background: #1e1e1e; color: #eee; margin: 0; padding: 0; height: 100%;
                 font-family: Menlo, Consolas, monospace; }
    #terminal { padding: 8px; height: calc(100vh - 16px); }
    #status { position: fixed; top: 4px; right: 8px; font-size: 11px; opacity: 0.6; }
  </style>
</head>
<body>
  <div id=\"status\">connecting…</div>
  <div id=\"terminal\"></div>
  <script type=\"module\">
    import { init, Terminal } from '/static/ghostty-web/ghostty-web.js';

    const statusEl = document.getElementById('status');
    function setStatus(s) { statusEl.textContent = s; }

    await init();

    const term = new Terminal({
      cols: 100, rows: 30,
      theme: { background: '#1e1e1e', foreground: '#eeeeee' }
    });
    term.open(document.getElementById('terminal'));
    window.__ghosttyTerm = term;  // exposed for demo/shell-smoke.mjs

    const wsProto = location.protocol === 'https:' ? 'wss' : 'ws';
    const ws = new WebSocket(wsProto + '://' + location.host + '/ws/echo');
    ws.binaryType = 'arraybuffer';

    ws.onopen    = () => { setStatus('connected'); term.write('\\x1b[32m[echo server]\\x1b[0m\\r\\n'); };
    ws.onclose   = () => setStatus('disconnected');
    ws.onerror   = () => setStatus('ws error');
    ws.onmessage = (e) => {
      term.write(typeof e.data === 'string' ? e.data : new Uint8Array(e.data));
    };

    term.onData((data) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(data);
    });
  </script>
</body>
</html>")
