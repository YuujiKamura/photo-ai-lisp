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

(defun %utf8-encode-char (code buf)
  "Append the UTF-8 byte sequence for CODE-POINT CODE to adjustable byte
   vector BUF. Handles the full Unicode range (U+0080..U+10FFFF).
   Chars <= 0x7F are handled by the caller for the LF→CR rewrite and
   latin-1 passthrough path, so this helper only needs to cover multi-byte
   sequences starting at U+0080."
  (cond
    ((< code #x80)
     ;; Caller already handled 0x00-0x7F via the latin-1 passthrough path.
     ;; Reached here only if a caller bypasses the guard; emit as-is.
     (vector-push-extend code buf))
    ((< code #x800)
     ;; 2-byte: 110xxxxx 10xxxxxx
     (vector-push-extend (logior #xC0 (ash code -6)) buf)
     (vector-push-extend (logior #x80 (logand code #x3F)) buf))
    ((< code #x10000)
     ;; 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
     (vector-push-extend (logior #xE0 (ash code -12)) buf)
     (vector-push-extend (logior #x80 (logand (ash code -6) #x3F)) buf)
     (vector-push-extend (logior #x80 (logand code #x3F)) buf))
    (t
     ;; 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
     (vector-push-extend (logior #xF0 (ash code -18)) buf)
     (vector-push-extend (logior #x80 (logand (ash code -12) #x3F)) buf)
     (vector-push-extend (logior #x80 (logand (ash code -6) #x3F)) buf)
     (vector-push-extend (logior #x80 (logand code #x3F)) buf))))

(defun %normalize-child-input (s)
  "Normalize S for writing to the child's stdin. Transforms:

    - Chars <= 0x7F (ASCII/C0): LF (10) is translated to CR (13) so that
      cmd.exe under our ConPTY bridge interprets Enter correctly.
      Consecutive CRs are collapsed to one to prevent double-Enter
      (see commit de778f7). All other ASCII/C0 bytes pass through as-is.

    - Chars 0x80-0xFF (latin-1 supplement): pass through as their byte
      values unchanged (latin-1 bijection).

    - Chars > 0xFF (CJK, emoji, …): UTF-8 encoded as multi-byte byte
      sequences and appended directly. The child stdin stream uses
      :external-format :latin-1 which is byte-transparent via SBCL's
      bivalent fd-stream — write-sequence of the resulting (unsigned-byte 8)
      vector delivers the UTF-8 octets to the child verbatim.
      The ConPTY bridge passes them through, and cmd.exe / claude etc.
      receive the correct UTF-8 encoding of the IME-committed text."
  (let ((buf (make-array (length s) :element-type '(unsigned-byte 8)
                                    :fill-pointer 0 :adjustable t))
        (prev-cr nil))
    (loop for c across s
          for code = (char-code c)
          do (cond
               ;; NUL / control chars that have no sensible terminal meaning
               ;; (but leave C0 alone except the LF→CR rewrite below)
               ((= code 0)
                ;; skip NUL — it would terminate C strings in the child
                nil)
               ;; ASCII range (0x01-0xFF): apply LF→CR and CR-dedup
               ((<= code #xFF)
                (let ((b (if (= code 10) 13 code)))
                  (unless (and prev-cr (= b 13))
                    (vector-push-extend b buf))
                  (setf prev-cr (= b 13))))
               ;; Above latin-1: UTF-8 encode.
               ;; Reset prev-cr so a CR immediately before a CJK char does
               ;; not get coalesced with a later CR.
               (t
                (setf prev-cr nil)
                (%utf8-encode-char code buf))))
    buf))

(defun shell-broadcast-input (text)
  "Write TEXT to the child stdin of every connected shell client.
   Returns the number of clients reached. TEXT is recorded in the
   trace ring as :in (dir) for observability. The terminator contract
   is intentionally forgiving: callers may send LF, CR, CRLF, LFLF,
   or CRCR and %normalize-child-input collapses any run to a single
   CR (one Enter). Callers don't need to know which terminator the
   wire expects."
  (let ((recipients (bordeaux-threads:with-lock-held (*shell-clients-lock*)
                      (copy-list *shell-clients*))))
    (shell-trace-record :in text)
    (let ((safe (%normalize-child-input text)))
      (loop for c in recipients
            for child = (shell-client-child c)
            when child
              count (handler-case
                        (progn
                          (write-sequence safe (child-process-stdin child))
                          (finish-output (child-process-stdin child))
                          t)
                      (error () nil))))))

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
  "Sanitized one-line preview of S for the trace ring. Tolerates NIL
   chars (which can appear when a WS text-frame UTF-8 decode yields
   an undefined code-point) by treating them as '.', so the trace
   can't itself throw and crash whatever thread is recording."
  (let* ((s (or s ""))
         (n (min 80 (length s))))
    (with-output-to-string (out)
      (loop for i below n
            for c = (char s i)
            for code = (and (characterp c) (char-code c))
            do (write-char
                (cond
                  ((null code)                         #\.)
                  ((= code 13)                         #\space)
                  ((= code 10)                         #\space)
                  ((< code 32)                         #\.)
                  (t                                   c))
                out)))))

(defun shell-trace-record (dir message)
  "Append one trace entry. DIR is :in (bytes written to child stdin),
   :out (bytes read from child stdout), or :meta (observability markers
   from internal plumbing such as picker auto-inject). MESSAGE is the
   string."
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

(defun %demo-agent-argv ()
  "When PHOTO_AI_LISP_DEMO_AGENT is set in the environment, return it
   as a parsed argv list so /ws/shell spawns that command directly as
   the demo child (no pick-agent picker menu, no deckpilot hop).
   Returns NIL when the var is unset or empty.

   T2.h pivot: the Tier-2 demo round-trip runs entirely inside the
   Lisp-owned /ws/shell child instead of a separate ghostty-win + CP
   hop, so the iframe-visible child *is* the INPUT recipient.

   Space-split is intentionally naive — it covers the documented
   command shape (`claude --dangerously-skip-permissions --model sonnet`)
   and similar plain flag lists. Callers that need quoting / embedded
   spaces must expand this."
  (let ((raw (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT")))
    (when (and raw (plusp (length raw)))
      (loop with start = 0 with tokens = nil
            for i below (length raw)
            when (char= (char raw i) #\Space)
              do (when (< start i)
                   (push (subseq raw start i) tokens))
                 (setf start (1+ i))
            finally (when (< start (length raw))
                      (push (subseq raw start (length raw)) tokens))
                    (return (nreverse tokens))))))

(defun %shell-argv ()
  ;; T2.h pivot: when PHOTO_AI_LISP_DEMO_AGENT is set, spawn that command
  ;; directly instead of the platform shell. The picker auto-inject
  ;; (%auto-pick-agent) is also skipped in client-connected when this
  ;; argv overrides kicks in, so the demo child is the agent, not cmd.
  ;;
  ;; On Windows (no demo override), route through %default-argv so
  ;; cmd.exe runs under the conpty-bridge (real ConPTY). Without the
  ;; bridge, cmd sees piped stdin and LF is the only line terminator
  ;; it honors — contradicting %normalize-child-input's LF->CR rewrite
  ;; and breaking pick-agent.cmd auto-inject. %default-argv falls back
  ;; to bare cmd.exe if the bridge binary is missing.
  (or (%demo-agent-argv)
      (if (uiop:os-windows-p)
          (%default-argv)
          (list "/bin/bash" "--norc" "--noprofile"))))

(defun %scrub-for-utf8 (s)
  "Collapse anything hunchensocket's UTF-8 text-frame encoder cannot
   handle down to ASCII '?'. That includes: NIL chars (seen when the
   child stream yields undefined code-points under edge cases), lone
   UTF-16 surrogates (#xD800–#xDFFF), and anything past the Unicode
   cap #x10FFFF. Result is guaranteed to be a simple-base-string of
   only safe code-points, so send-text-message never throws the
   'NIL is not of type (MOD 1114112)' error that otherwise cascades
   into an outer handler-bind and closes the WS with status 1011."
  (with-output-to-string (out)
    (loop for c across s
          for code = (and (characterp c) (char-code c))
          do (write-char (cond
                           ((null code) #\?)
                           ((<= #xD800 code #xDFFF) #\?)
                           ((> code #x10FFFF) #\?)
                           (t c))
                         out))))

;;; 2c — stdout pump: read chunks from child stdout, push to websocket.
;;; Binary frame transport: child stdout bytes are forwarded as raw
;;; octets over a WebSocket binary frame, so UTF-8 multi-byte sequences
;;; (box drawing from claude/gemini TUIs, Japanese text) survive the
;;; Lisp→browser hop. The previous text-frame path did (code-char b)
;;; per byte and then UTF-8-encoded the resulting codepoints, which
;;; doubled every non-ASCII byte and broke ghostty-web's UTF-8 parser.
(defun %stdout-pump (client child)
  (let ((out (child-process-stdout child))
        (buf (make-array 512 :element-type '(unsigned-byte 8)
                             :adjustable t :fill-pointer 0)))
    (handler-case
        (loop
          (cond
            ((listen out)
             (handler-case
                 (let ((b (read-byte out nil :eof)))
                   (cond
                     ((eq b :eof) (return))
                     ((null b) nil)   ; defensive: some streams return NIL
                     (t (vector-push-extend b buf))))
               (error () nil)))
            ((plusp (length buf))
             (let* ((chunk (copy-seq buf))
                    ;; Trace preview is Latin-1 mapped for display only;
                    ;; the wire carries the raw octets unchanged.
                    (preview (map 'string
                                  (lambda (b) (code-char (logand b #xFF)))
                                  chunk)))
               (shell-trace-record :out preview)
               (handler-case
                   (hunchensocket:send-binary-message client chunk)
                 (error (e)
                   (format *error-output* "PUMP-SEND-ERR type=~a msg=~a~%"
                           (type-of e) e)
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
        ;; T2.h pivot: when the demo agent argv override is active, the
        ;; child IS the agent — don't inject a picker into claude's stdin.
        (when (and *auto-pick-agent* (not (%demo-agent-argv)))
          (bordeaux-threads:make-thread
           (lambda ()
             (sleep 0.4)
             (shell-trace-record :meta "[picker-inject:enter]")
             (handler-case
                 (let ((stdin (child-process-stdin child))
                       ;; Single LF only. %normalize-child-input flips it
                       ;; to CR (one Enter) so cmd runs the batch and set/p
                       ;; inside pick-agent.cmd keeps blocking for the
                       ;; user's actual choice. Sending \r\n (= \r\r after
                       ;; normalize) races ahead and answers set/p with an
                       ;; empty line before the user can press a digit.
                       (line  (format nil "~a~c"
                                      (%agent-picker-command)
                                      #\Newline)))
                   (write-sequence (%normalize-child-input line) stdin)
                   (finish-output stdin)
                   (shell-trace-record :meta "[picker-inject:wrote]"))
               (error (e)
                 (shell-trace-record
                  :meta (format nil "[picker-inject:ERR ~a ~a]"
                                (type-of e) e)))))
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

;;; Server-initiated orderly teardown of every active /ws/shell connection.
;;; Call this BEFORE hunchentoot:stop to drain CLOSE_WAIT sockets on Windows.
;;;
;;; Why: on Windows the AFD/afd.sys driver holds a TCP socket in CLOSE_WAIT
;;; until the server explicitly closes its side. hunchentoot:stop merely stops
;;; accepting new connections; it does NOT close already-accepted streaming
;;; sockets that are being handled by per-connection threads. Chrome's
;;; auto-reconnect loop after a hub kill leaves 40+ CLOSE_WAIT sockets that
;;; prevent rebind on the same port for minutes.
;;;
;;; Fix: before stopping the acceptor we walk *shell-clients*, kill each
;;; child process (so no new output arrives), send a WS close frame
;;; (opcode 0x8, status 1001 "going away"), and then force-close the
;;; underlying Lisp stream. The force-close triggers the OS to send FIN/RST,
;;; immediately transitioning the Windows socket out of CLOSE_WAIT.
(defun close-shell-clients ()
  "Forcibly close every active /ws/shell client and its child process.
Sends a WebSocket 1001 close frame then closes the TCP stream so Windows
does not leave the socket in CLOSE_WAIT after the acceptor stops.
Returns the number of clients closed."
  (let ((snapshot (bordeaux-threads:with-lock-held (*shell-clients-lock*)
                    (prog1 (copy-list *shell-clients*)
                      (setf *shell-clients* '())))))
    (dolist (client snapshot)
      ;; 1. Kill the child process first so the stdout pump thread exits
      ;;    and stops writing to the WS after we close it.
      (let ((child (shell-client-child client)))
        (when child
          (ignore-errors (kill-child child))
          (setf (shell-client-child client) nil)))
      ;; 2. Send WS close frame (1001 = going away) so Chrome transitions
      ;;    its side to CLOSE_WAIT instead of keeping the connection open.
      (ignore-errors
        (hunchensocket:close-connection client :status 1001 :reason "server shutdown"))
      ;; 3. Force-close the underlying stream. This is what actually tells
      ;;    the Windows TCP stack to send FIN and release the socket fd.
      (ignore-errors
        (close (slot-value client 'hunchensocket::output-stream) :abort t)))
    (length snapshot)))

;;; Resize protocol: emit 7-byte OOB magic frame to the bridge stdin.
;;; Frame layout: SOH(0x01) 'R'(0x52) 'Z'(0x5A) cols-lo cols-hi rows-lo rows-hi
;;; (cols and rows are u16 little-endian). The bridge's resizeAwareCopy
;;; intercepts this sequence, calls ResizePseudoConsole, and swallows the 7
;;; bytes so they never reach the child process.
(defun shell-resize (child cols rows)
  "Send a resize frame to CHILD's stdin. COLS and ROWS are positive integers.
   Returns T on success, NIL if the child is absent or write fails."
  (when (and child (plusp cols) (plusp rows))
    (let ((frame (make-array 7 :element-type '(unsigned-byte 8))))
      (setf (aref frame 0) #x01)   ; SOH
      (setf (aref frame 1) #x52)   ; 'R'
      (setf (aref frame 2) #x5A)   ; 'Z'
      ;; cols u16 LE
      (setf (aref frame 3) (logand cols #xFF))
      (setf (aref frame 4) (logand (ash cols -8) #xFF))
      ;; rows u16 LE
      (setf (aref frame 5) (logand rows #xFF))
      (setf (aref frame 6) (logand (ash rows -8) #xFF))
      (handler-case
          (progn
            (write-sequence frame (child-process-stdin child))
            (finish-output (child-process-stdin child))
            t)
        (error (e)
          (format *error-output* "RESIZE-ERR cols=~a rows=~a err=~a~%" cols rows e)
          (finish-output *error-output*)
          nil)))))

;;; 2b — text message received: write to child stdin.
;;; hunchensocket hands us the already-UTF-8-decoded string. If the frame
;;; contained bytes that can't round-trip through latin-1 (what the child
;;; stdin stream expects), write-string will raise. Scrub down to <=0xFF
;;; before the write and log any residual failure visibly — silent
;;; ignore-errors here masked real bugs (WS died immediately after an
;;; un-encodable byte hit the child stream).
;;;
;;; Resize messages arrive as JSON: {"type":"resize","cols":N,"rows":M}
;;; They are dispatched to shell-resize and do NOT touch child stdin directly.
(defmethod hunchensocket:text-message-received ((resource shell-resource)
                                                  (client   shell-client)
                                                  message)
  ;; hunchensocket's outer handler-bind in read-handle-loop closes the
  ;; connection with status 1011 on ANY unhandled error here. Scrub +
  ;; handler-case so a single bad byte never drops the whole session.
  (handler-case
      (let ((child (shell-client-child client)))
        ;; Attempt to parse as JSON for typed control messages.
        ;; shasht:read-json returns NIL on parse failure (not a control msg).
        (let* ((parsed (handler-case
                           (shasht:read-json (make-string-input-stream message))
                         (error () nil)))
               (msg-type (and (hash-table-p parsed)
                              (gethash "type" parsed))))
          (cond
            ;; {"type":"resize","cols":N,"rows":M}
            ((equal msg-type "resize")
             (let ((cols (gethash "cols" parsed))
                   (rows (gethash "rows" parsed)))
               (when (and cols rows (plusp cols) (plusp rows))
                 (shell-trace-record :meta
                                     (format nil "[resize cols=~a rows=~a]" cols rows))
                 (when child
                   (shell-resize child (floor cols) (floor rows))))))
            ;; Not a control message — forward as terminal input.
            (t
             (shell-trace-record :in message)
             (when child
               (let ((safe (%normalize-child-input message)))
                 (write-sequence safe (child-process-stdin child))
                 (finish-output (child-process-stdin child))))))))
    (error (e)
      (format *error-output* "WS-IN-ERR type=~a msg=~a~%" (type-of e) e)
      (finish-output *error-output*))))

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
    html, body {
      background: #1e1e1e; margin: 0; padding: 0; height: 100%;
      /* Kill every shaping feature that could shift cell boundaries.
         ghostty-web's canvas renderer measures glyph advance via the
         OS font stack, so disabling ligatures/kerning/contextual-alts
         here keeps each cell to a fixed integer advance. */
      font-feature-settings: 'kern' 0, 'liga' 0, 'dlig' 0, 'clig' 0, 'calt' 0;
      font-variant-ligatures: none;
      font-kerning: none;
      text-rendering: geometricPrecision;
    }
    #shell-root { position: relative; width: 100%; height: 100%; }
    #terminal { width: 100%; height: 100%; }
    /* Snap the WASM renderer's backing canvas to device pixels so row
       height doesn't drift by a fractional pixel across scrolls. */
    #terminal canvas {
      image-rendering: crisp-edges;
      transform: translateZ(0);
    }
    /* IME sink: transparent overlay textarea that captures CJK composition
       events. It sits above the canvas (z-index) so that when focused it
       receives compositionstart/end from the OS IME. Opacity 0 + no caret
       keeps it invisible while the OS-native IME popup is still positioned
       relative to it (browsers respect the element bounding box for IME
       popup placement even when opacity is 0). pointer-events:none on the
       textarea itself prevents it from eating mouse clicks meant for the
       canvas — focus is set programmatically on pointerdown. */
    #ime-sink {
      position: absolute;
      inset: 0;
      opacity: 0;
      background: transparent;
      border: none;
      outline: none;
      resize: none;
      padding: 0;
      margin: 0;
      z-index: 10;
      caret-color: transparent;
      pointer-events: none;
      font-size: 14px;
    }
  </style>
</head>
<body>
  <div id=\"shell-root\">
    <div id=\"terminal\"></div>
    <textarea id=\"ime-sink\" aria-hidden=\"true\" autocorrect=\"off\"
              autocapitalize=\"off\" spellcheck=\"false\"
              tabindex=\"-1\"></textarea>
  </div>
  <script type=\"module\">
    // Renderer: ghostty-web WASM bundle served from /vendor/ by the Lisp hub.
    // PTY lives on the Lisp side at /ws/shell. Keep the protocol dumb so
    // /api/inject and the picker auto-inject (term.lisp client-connected)
    // both continue to reach this PTY without a separate node daemon.
    // FitAddon is exported from the same bundle and wires ResizeObserver
    // to call term.resize() whenever the container dimensions change.
    import { init, Terminal, FitAddon } from '/vendor/ghostty-web.js';
    await init();

    // Font stack aimed at WT-parity: Cascadia (ships with Windows
    // Terminal, ligature-free Mono variant first), then Meiryo UI
    // as the CJK fallback that keeps ambiguous-width glyphs on a
    // full cell, then Consolas as the universal Windows monospace.
    //
    // Initial size is deliberately unconstrained (cols/rows omitted so
    // the Terminal defaults) — FitAddon will compute and apply the real
    // dimensions from the container immediately after open().

    const term = new Terminal({
      fontFamily: \"'Cascadia Mono', 'Cascadia Code', 'Meiryo UI', Consolas, 'Lucida Console', monospace\",
      fontSize: 14,
      theme: { background: '#1e1e1e', foreground: '#d4d4d4' },
    });
    const container = document.getElementById('terminal');
    await term.open(container);

    // FitAddon: measures the container and calls term.resize() to match.
    // observeResize() wires a ResizeObserver so every future browser-window
    // resize also fires fit().
    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    fitAddon.fit();
    fitAddon.observeResize();

    // --- IME overlay textarea (issue #36) ---
    // ghostty-web's hidden textarea has clip-path:inset(50%) which hides
    // the element entirely including the caret anchor; some OS IME
    // implementations position the candidate popup relative to the focused
    // element's bounding rect and end up placing it off-screen (or simply
    // not attaching because the rect is empty).  We add a second, full-size
    // overlay textarea that the IME can use as its anchor.  It is transparent
    // and non-interactive for mouse events, so the canvas still receives
    // pointer events and ghost-web's own input path keeps working for ASCII.
    //
    // Dual-path guarantee:
    //   IME path:   compositionend on ime-sink → ws.send(e.data)
    //   ASCII path: term.onData               → ws.send(data)  [unchanged]
    // There is no double-send risk: compositionend does not re-fire on
    // term.onData because ghostty-web guards keydown with isComposing.
    const ime = document.getElementById('ime-sink');
    let composing = false;

    ime.addEventListener('compositionstart', () => { composing = true; });
    ime.addEventListener('compositionupdate', () => { /* preedit: OS popup handles it */ });
    ime.addEventListener('compositionend', (e) => {
      composing = false;
      const s = e.data || '';
      if (s && ws && ws.readyState === WebSocket.OPEN) {
        ws.send(s.replace(/\\r/g, '\\n'));
      }
      ime.value = '';
    });
    // Direct (non-IME) input that lands on ime-sink when it has focus
    // (e.g. ASCII keys on some mobile keyboards that route through beforeinput
    // rather than keydown): forward to WS and clear value to prevent
    // accumulation.  Guard on !isComposing to avoid double-send with the
    // compositionend handler above.
    ime.addEventListener('input', (e) => {
      if (e.isComposing || composing) return;
      const t = ime.value;
      if (t && ws && ws.readyState === WebSocket.OPEN) {
        ws.send(t.replace(/\\r/g, '\\n'));
      }
      ime.value = '';
    });

    // On any pointer-down in the terminal area: give focus to the ime-sink
    // textarea (so IME attaches to it) and also call term.focus() so
    // ghostty-web's ASCII keydown path remains active via the container.
    // The textarea has pointer-events:none so this listener must be on the
    // shell-root wrapper, not on the textarea itself.
    document.getElementById('shell-root').addEventListener('pointerdown', () => {
      term.focus();          // ghostty-web keeps ASCII input working
      ime.focus();           // IME now anchors to the full-size overlay
    });
    window.addEventListener('focus', () => {
      term.focus();
      ime.focus();
    });

    // Initial focus
    term.focus();
    ime.focus();

    let ws = null, reconnectDelay = 500;
    function connect() {
      ws = new WebSocket('ws://' + location.host + '/ws/shell');
      // Binary frames carry raw PTY octets so UTF-8 multi-byte sequences
      // (box drawing, Japanese, emoji) reach the VT parser intact.
      ws.binaryType = 'arraybuffer';
      ws.onopen = () => {
        reconnectDelay = 500;
        // On (re)connect, immediately push the current terminal dimensions
        // to the bridge so the ConPTY and TUI stay in sync with the browser.
        const { cols, rows } = term;
        if (cols && rows) {
          ws.send(JSON.stringify({ type: 'resize', cols, rows }));
        }
      };
      ws.onmessage = (e) => {
        term.write(typeof e.data === 'string' ? e.data : new Uint8Array(e.data));
      };
      ws.onclose = () => {
        term.write('\\r\\n\\x1b[31m[disconnected — retrying]\\x1b[0m\\r\\n');
        setTimeout(connect, reconnectDelay);
        reconnectDelay = Math.min(reconnectDelay * 2, 5000);
      };
      // Browser fires onerror before onclose on most drop scenarios.
      // The onclose handler already shows '[disconnected — retrying]'
      // and reconnects, so a separate '[ws error]' line is just noise.
      ws.onerror = () => {};
    }
    connect();

    // Forward terminal resize events to the bridge via the OOB protocol.
    // The bridge's resizeAwareCopy detects the JSON control message,
    // calls ResizePseudoConsole, and strips the bytes from the child's stdin.
    term.onResize(({ cols, rows }) => {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'resize', cols, rows }));
      }
    });

    // No client-side local echo. cmd.exe in piped-stdin mode still
    // echoes every command line it reads before executing it, so
    // echoing locally double-prints every character the user types.
    // Downside: `set /p` style prompts (e.g. scripts/pick-agent.cmd)
    // stay silent while the user types — inherent cmd-on-pipe
    // limitation, fixed only by running the child under a real ConPTY.
    //
    // Hunchensocket + flexi-streams crashes a text frame that contains
    // a bare CR byte (0x0D) with 'NIL is not of type (MOD 1114112)',
    // cascading into an outer handler-bind and closing the WS with
    // 1011 Internal Error. Translate CR -> LF on the wire; cmd.exe
    // accepts LF-terminated input just fine, and the WS stays healthy.
    term.onData((data) => {
      if (ws && ws.readyState !== WebSocket.OPEN) return;
      ws.send(data.replace(/\\r/g, '\\n'));
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
