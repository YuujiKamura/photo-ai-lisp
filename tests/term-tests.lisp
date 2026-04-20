(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; UT2 — unit tests for src/term.lisp
;;; Tests class hierarchy, resource instances, URL dispatch, dispatch table,
;;; and HTML page content.  No server is started; WebSocket protocol methods
;;; are not exercised (integration territory).

;;; Minimal mock to drive hunchentoot:script-name without a real HTTP request.
(defclass %mock-request ()
  ((%path :initarg :path)))

(defmethod hunchentoot:script-name ((req %mock-request))
  (slot-value req '%path))

(defun %make-req (path)
  (make-instance '%mock-request :path path))

;; UT2a: ws-easy-acceptor inherits from both WebSocket and easy-acceptor.
(test term-ws-easy-acceptor-inherits-websocket-acceptor
  (is-true (subtypep 'photo-ai-lisp::ws-easy-acceptor
                     'hunchensocket:websocket-acceptor)
           "ws-easy-acceptor must be a subtype of websocket-acceptor"))

(test term-ws-easy-acceptor-inherits-easy-acceptor
  (is-true (subtypep 'photo-ai-lisp::ws-easy-acceptor
                     'hunchentoot:easy-acceptor)
           "ws-easy-acceptor must be a subtype of easy-acceptor"))

;; UT2b: global resource instances have the expected types.
(test term-echo-resource-type
  (is-true (typep photo-ai-lisp::*echo-resource*
                  'photo-ai-lisp::echo-resource)
           "*echo-resource* should be an echo-resource instance"))

(test term-shell-resource-type
  (is-true (typep photo-ai-lisp::*shell-resource*
                  'photo-ai-lisp::shell-resource)
           "*shell-resource* should be a shell-resource instance"))

;; UT2c: %find-echo-resource dispatches on /ws/echo, returns nil elsewhere.
(test term-find-echo-resource-match
  (is (eq photo-ai-lisp::*echo-resource*
          (photo-ai-lisp::%find-echo-resource (%make-req "/ws/echo")))
      "%find-echo-resource should return *echo-resource* for /ws/echo"))

(test term-find-echo-resource-no-match
  (is (null (photo-ai-lisp::%find-echo-resource (%make-req "/ws/shell")))
      "%find-echo-resource should return nil for /ws/shell")
  (is (null (photo-ai-lisp::%find-echo-resource (%make-req "/")))
      "%find-echo-resource should return nil for /"))

;; UT2d: %find-shell-resource dispatches on /ws/shell, returns nil elsewhere.
(test term-find-shell-resource-match
  (is (eq photo-ai-lisp::*shell-resource*
          (photo-ai-lisp::%find-shell-resource (%make-req "/ws/shell")))
      "%find-shell-resource should return *shell-resource* for /ws/shell"))

(test term-find-shell-resource-no-match
  (is (null (photo-ai-lisp::%find-shell-resource (%make-req "/ws/echo")))
      "%find-shell-resource should return nil for /ws/echo")
  (is (null (photo-ai-lisp::%find-shell-resource (%make-req "/")))
      "%find-shell-resource should return nil for /"))

;; UT2e: *websocket-dispatch-table* contains both dispatch functions.
(test term-dispatch-table-has-echo-fn
  (is-true (find 'photo-ai-lisp::%find-echo-resource
                 hunchensocket:*websocket-dispatch-table*)
           "*websocket-dispatch-table* should contain %find-echo-resource"))

(test term-dispatch-table-has-shell-fn
  (is-true (find 'photo-ai-lisp::%find-shell-resource
                 hunchensocket:*websocket-dispatch-table*)
           "*websocket-dispatch-table* should contain %find-shell-resource"))

;; UT2f: term-page returns HTML containing "xterm.js".
;;  hunchentoot:*reply* must be bound to avoid an unbound-variable error from
;;  (setf (content-type*) ...) inside the handler.
(test term-page-contains-xterm-js
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (let ((html (photo-ai-lisp::term-page)))
      (is-true (stringp html)
               "term-page should return a string")
      (is-true (search "xterm.js" html)
               "term-page HTML should reference xterm.js"))))

;; UT2g: shell-page renders a ghostty-web-backed terminal.
;; The page used to import xterm.js from a CDN; commit 7247996 replaced
;; that with the vendored ghostty-web WASM bundle served from /vendor/
;; by the Lisp hub itself. Assert on the current shape.
(test shell-page-imports-ghostty-web
  (let ((hunchentoot:*reply* (make-instance 'hunchentoot:reply)))
    (let ((html (photo-ai-lisp::shell-page)))
      (is-true (stringp html)
               "shell-page should return a string")
      (is-true (search "/vendor/ghostty-web.js" html)
               "shell-page should import the vendored ghostty-web bundle")
      (is-true (search "/ws/shell" html)
               "shell-page should connect to /ws/shell"))))

;;; UT2h — agent picker (commit 31b0f1f): auto-inject on /ws/shell connect.

;; %agent-picker-command returns the platform-appropriate script invocation.
(test term-agent-picker-command-platform
  (let ((cmd (photo-ai-lisp::%agent-picker-command)))
    (is-true (stringp cmd)
             "%agent-picker-command should return a string")
    (if (uiop:os-windows-p)
        (is (search "pick-agent.cmd" cmd)
            "on Windows should invoke pick-agent.cmd")
        (is (search "pick-agent.sh" cmd)
            "on non-Windows should invoke pick-agent.sh"))))

;; %agent-picker-command points at a file that actually exists on disk.
;; Path is relative to the server's cwd (repo root via scripts/demo.sh).
(test term-agent-picker-script-exists
  (let* ((cmd  (photo-ai-lisp::%agent-picker-command))
         (rel  (if (uiop:os-windows-p)
                   cmd
                   ;; strip leading "sh " so we can probe the file.
                   (subseq cmd 3)))
         (path (merge-pathnames
                (uiop:parse-unix-namestring
                 (substitute #\/ #\\ rel))
                (asdf:system-source-directory :photo-ai-lisp))))
    (is-true (probe-file path)
             (format nil "picker script must exist on disk: ~a" path))))

;; *auto-pick-agent* defaults reflect the DISABLE_AGENT_PICKER env var.
;; Can't clobber the global defvar during tests, so just assert the
;; invariant: it's boolean, and NIL iff env var is literally "1".
(test term-auto-pick-agent-default-matches-env
  (let ((env (uiop:getenv "DISABLE_AGENT_PICKER")))
    (if (equal env "1")
        (is-false photo-ai-lisp::*auto-pick-agent*
                  "DISABLE_AGENT_PICKER=1 should disable auto-pick")
        (is-true photo-ai-lisp::*auto-pick-agent*
                 "picker should be enabled when DISABLE_AGENT_PICKER is unset"))))

;;; UT2i — %normalize-child-input: latin-1 scrub + LF->CR for ConPTY.
;;; Justified by the conpty-bridge integration test (ConPTY needs CR
;;; to fire the Enter key); the WS frame path must flip LF back to CR
;;; before writing into the child, or cmd.exe buffers lines forever.

(test normalize-child-input-plain-ascii-passthrough
  (is (string= "hello"
               (photo-ai-lisp::%normalize-child-input "hello"))
      "pure ASCII should survive untouched"))

(test normalize-child-input-empty-string
  (is (string= "" (photo-ai-lisp::%normalize-child-input ""))
      "empty string should stay empty"))

(test normalize-child-input-lf-becomes-cr
  (is (string= (string #\Return)
               (photo-ai-lisp::%normalize-child-input (string #\Newline)))
      "a bare LF must be rewritten as CR so ConPTY treats it as Enter"))

(test normalize-child-input-lf-inside-line
  (is (string= (format nil "echo hi~C" #\Return)
               (photo-ai-lisp::%normalize-child-input
                (format nil "echo hi~C" #\Newline)))
      "LF terminating a command should be flipped to CR"))

(test normalize-child-input-cr-left-alone
  (is (string= (string #\Return)
               (photo-ai-lisp::%normalize-child-input (string #\Return)))
      "an already-CR byte must pass through without duplication"))

(test normalize-child-input-multi-lf-all-flipped
  (is (string= (format nil "a~Cb~Cc" #\Return #\Return)
               (photo-ai-lisp::%normalize-child-input
                (format nil "a~Cb~Cc" #\Newline #\Newline)))
      "every LF in the input should be flipped to CR"))

(test normalize-child-input-drops-out-of-latin1
  ;; The child stream is :latin-1; anything above #xFF cannot round-
  ;; trip and would otherwise raise on write. CL doesn't support
  ;; \xNN string escapes, so build the expected string via code-char.
  (let* ((in  (format nil "ok~C~Cend" (code-char #x00A9) (code-char #x2603)))
         (exp (format nil "ok~Cend" (code-char #x00A9)))
         (out (photo-ai-lisp::%normalize-child-input in)))
    (is (string= exp out)
        "keeps <=0xFF chars and drops anything past latin-1 range")))

(test normalize-child-input-drops-surrogate-like-code
  ;; Surrogates (U+D800..U+DFFF) never appear in valid Unicode strings
  ;; but hunchensocket's decoder occasionally synthesizes them from
  ;; bad UTF-8; they're >0xFF so must be dropped.
  (let ((in (format nil "x~Cy" (code-char #xD800))))
    (is (string= "xy"
                 (photo-ai-lisp::%normalize-child-input in))
        "lone surrogates must be dropped")))
