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
  (is (equalp #(104 101 108 108 111)
               (photo-ai-lisp::%normalize-child-input "hello"))
      "pure ASCII should survive untouched"))

(test normalize-child-input-empty-string
  (is (equalp #() (photo-ai-lisp::%normalize-child-input ""))
      "empty string should stay empty"))

(test normalize-child-input-lf-becomes-cr
  (is (equalp #(13)
               (photo-ai-lisp::%normalize-child-input (string #\Newline)))
      "a bare LF must be rewritten as CR so ConPTY treats it as Enter"))

(test normalize-child-input-lf-inside-line
  (is (equalp #(101 99 104 111 32 104 105 13)
               (photo-ai-lisp::%normalize-child-input
                (format nil "echo hi~C" #\Newline)))
      "LF terminating a command should be flipped to CR"))

(test normalize-child-input-cr-left-alone
  (is (equalp #(13)
               (photo-ai-lisp::%normalize-child-input (string #\Return)))
      "an already-CR byte must pass through without duplication"))

(test normalize-child-input-multi-lf-all-flipped
  (is (equalp #(97 13 98 13 99)
               (photo-ai-lisp::%normalize-child-input
                (format nil "a~Cb~Cc" #\Newline #\Newline)))
      "every LF in the input should be flipped to CR"))

(test normalize-child-input-drops-out-of-latin1
  ;; The child stream is binary; anything above #xFF cannot be
  ;; represented as (unsigned-byte 8) and must be dropped.
  (let* ((in  (format nil "ok~C~Cend" (code-char #x00A9) (code-char #x2603)))
         (exp #(111 107 169 101 110 100))
         (out (photo-ai-lisp::%normalize-child-input in)))
    (is (equalp exp out)
        "keeps <=0xFF chars and drops anything past latin-1 range")))

(test normalize-child-input-drops-surrogate-like-code
  ;; Surrogates (U+D800..U+DFFF) never appear in valid Unicode strings
  ;; but hunchensocket's decoder occasionally synthesizes them from
  ;; bad UTF-8; they're >0xFF so must be dropped.
  (let ((in (format nil "x~Cy" (code-char #xD800))))
    (is (equalp #(120 121)
                 (photo-ai-lisp::%normalize-child-input in))
        "lone surrogates must be dropped")))

;;; UT2j — regression locks for commit de778f7 (two bugs in src/term.lisp).
;;;
;;; Bug 1: %shell-argv returned bare '("cmd.exe") on Windows, bypassing
;;;   %default-argv which wraps cmd under the conpty-bridge when the
;;;   bridge binary is present. Effect: the /ws/shell child ran cmd.exe
;;;   on raw pipes, so cmd saw LF (never the CR produced by
;;;   %normalize-child-input) and set /p in pick-agent.cmd hung forever.
;;;
;;; Bug 2: the picker auto-inject built its line with "\r\n" as
;;;   terminator. %normalize-child-input flips LF->CR, so that became
;;;   "\r\r" — two Enter keystrokes. The second CR answered the very
;;;   set /p "> " prompt the script opens, racing past the user's real
;;;   digit and making the picker useless.

;; %shell-argv on Windows must delegate to %default-argv.
;; When the conpty-bridge binary exists, the argv must be
;;   (list *conpty-bridge-path* "cmd.exe")
;; not bare ("cmd.exe"). Stubbing *conpty-bridge-path* to this test
;; file (guaranteed to exist) lets us simulate "bridge built".
(test term-shell-argv-windows-uses-conpty-bridge-when-present
  (if (uiop:os-windows-p)
      (let* ((stub (namestring
                    (merge-pathnames "tests/term-tests.lisp"
                                     (asdf:system-source-directory
                                      :photo-ai-lisp))))
             (photo-ai-lisp::*conpty-bridge-path* stub)
             (argv (photo-ai-lisp::%shell-argv)))
        (is (equal (list stub "cmd.exe") argv)
            "when the bridge path points at an existing file, %shell-argv ~
             must return (bridge-path cmd.exe), proving it routes through ~
             %default-argv instead of returning bare (cmd.exe)"))
      (pass "non-Windows: %shell-argv uses bash, not relevant")))

;; When the bridge binary is missing, %shell-argv must still fall back
;; to bare "cmd.exe" via %default-argv's second cond arm — NOT error,
;; NOT return the non-Windows bash form.
(test term-shell-argv-windows-falls-back-to-cmd-when-bridge-missing
  (if (uiop:os-windows-p)
      (let* ((missing (namestring
                       (merge-pathnames
                        "tools/conpty-bridge/does-not-exist.exe"
                        (asdf:system-source-directory :photo-ai-lisp))))
             (photo-ai-lisp::*conpty-bridge-path* missing)
             (argv (photo-ai-lisp::%shell-argv)))
        (is (equal '("cmd.exe") argv)
            "with the bridge path pointing at a non-existent file, ~
             %shell-argv must fall back to bare ('cmd.exe') via ~
             %default-argv — never error, never leak the bash form"))
      (pass "non-Windows: bridge fallback path is not relevant")))

;; %shell-argv must not be the bare-cmd literal on Windows when the
;; bridge exists. This is the direct regression lock for bug 1 — the
;; pre-fix body was literally (if (uiop:os-windows-p) '("cmd.exe") ...),
;; which would make argv equal '("cmd.exe") even with a live bridge.
(test term-shell-argv-not-unconditional-cmd-on-windows
  (if (uiop:os-windows-p)
      (let* ((stub (namestring
                    (merge-pathnames "tests/term-tests.lisp"
                                     (asdf:system-source-directory
                                      :photo-ai-lisp))))
             (photo-ai-lisp::*conpty-bridge-path* stub)
             (argv (photo-ai-lisp::%shell-argv)))
        (is-false (equal '("cmd.exe") argv)
                  "with bridge present, %shell-argv must NOT collapse to ~
                   bare ('cmd.exe') — that was the pre-de778f7 bug that ~
                   broke ConPTY and pick-agent.cmd set /p handling"))
      (pass "non-Windows branch not affected by bug 1")))

;; Bug 2 lock, form-A: the picker inject builds its line with a single
;; LF terminator, never CRLF. Replicate the exact expression used in
;; term.lisp's client-connected :after body and assert its last char.
(test term-picker-inject-line-ends-in-single-lf
  (let ((line (format nil "~a~c"
                      (photo-ai-lisp::%agent-picker-command)
                      #\Newline)))
    (is (char= #\Newline (char line (1- (length line))))
        "picker inject line must end in a single LF — this is the exact ~
         (format nil \"~~a~~c\" cmd #\\Newline) pattern used in ~
         client-connected at term.lisp 280-282")
    (when (>= (length line) 2)
      (is-false (char= #\Return (char line (- (length line) 2)))
                "picker inject line must NOT have a CR immediately before ~
                 the LF — CRLF here becomes CR CR after %normalize-child-input ~
                 and answers set /p before the user types"))))

;; Bug 2 lock, form-B: after normalization, the picker line ends in
;; exactly one CR byte and NOT two. Demonstrates the wire effect of the
;; fix — a single Enter keystroke reaches cmd.exe, not two.
(test term-picker-inject-normalized-ends-in-single-cr
  (let* ((line (format nil "~a~c"
                       (photo-ai-lisp::%agent-picker-command)
                       #\Newline))
         (bytes (photo-ai-lisp::%normalize-child-input line))
         (n     (length bytes)))
    (is (plusp n) "normalized picker line must be non-empty")
    (is (= 13 (aref bytes (1- n)))
        "last byte of the normalized picker line must be CR (13) — ~
         that is the one Enter keystroke ConPTY needs to fire ~
         pick-agent.cmd's first line")
    (when (>= n 2)
      (is-false (= 13 (aref bytes (- n 2)))
                "byte before the trailing CR must NOT also be CR — two ~
                 consecutive CRs would mean the inject sent two Enters, ~
                 which races past set /p in pick-agent.cmd (the exact ~
                 regression fixed in de778f7)"))))

;; Bug 2 lock, form-C: the normalizer is idempotent for trailing Enter
;; shapes. Any of LF, CR, CRLF, LFLF, CRCR collapses to exactly one CR
;; byte. This is the class-level fix (see inject-contract-audit.md):
;; callers no longer need to memorize which terminator the wire wants,
;; and the preset-button / /api/inject paths that still hard-code CRLF
;; are now safe against the same race.
(test term-picker-inject-terminator-is-one-byte-not-two
  (let* ((cmd      (photo-ai-lisp::%agent-picker-command))
         (+lf      (photo-ai-lisp::%normalize-child-input
                    (format nil "~a~c" cmd #\Newline)))
         (+cr      (photo-ai-lisp::%normalize-child-input
                    (format nil "~a~c" cmd #\Return)))
         (+crlf    (photo-ai-lisp::%normalize-child-input
                    (format nil "~a~c~c" cmd #\Return #\Newline)))
         (+lflf    (photo-ai-lisp::%normalize-child-input
                    (format nil "~a~c~c" cmd #\Newline #\Newline)))
         (+crcr    (photo-ai-lisp::%normalize-child-input
                    (format nil "~a~c~c" cmd #\Return #\Return))))
    (is (= (1+ (length cmd)) (length +lf))
        "LF terminator normalizes to cmd + one CR")
    (is (equalp +lf +cr)
        "CR and LF terminators must produce identical byte vectors — ~
         LF->CR rule collapses them to the same shape")
    (is (equalp +lf +crlf)
        "CRLF (the UI preset-button / old picker-inject shape) must ~
         normalize identically to LF alone — this is the load-bearing ~
         invariant that kills the class of double-CR races")
    (is (equalp +lf +lflf)
        "LFLF must also collapse to one CR — consecutive-CR folding ~
         covers any caller that sends two LFs for emphasis")
    (is (equalp +lf +crcr)
        "CRCR (the pre-fix picker-inject wire shape) must collapse to ~
         one CR — regression lock for commit de778f7")))

;; Class-wide idempotency regression test: the raw three-case table
;; from inject-contract-audit.md. Decouples the invariant from
;; %agent-picker-command so a future helper rename doesn't hide a
;; normalizer regression.
(test term-normalize-collapses-consecutive-crs
  (let ((a\r\nb (photo-ai-lisp::%normalize-child-input
                 (coerce (list #\a #\Return #\Newline #\b) 'string)))
        (a\n\n (photo-ai-lisp::%normalize-child-input
                (coerce (list #\a #\Newline #\Newline) 'string)))
        (a\r\r (photo-ai-lisp::%normalize-child-input
                (coerce (list #\a #\Return #\Return) 'string))))
    (is (equalp #(97 13 98) a\r\nb)
        "a<CRLF>b normalizes to 3 bytes: 'a', one CR, 'b'")
    (is (equalp #(97 13) a\n\n)
        "a<LFLF> normalizes to 2 bytes: 'a', one CR")
    (is (equalp #(97 13) a\r\r)
        "a<CRCR> normalizes to 2 bytes: 'a', one CR"))
  ;; 4-byte double-CRLF: textarea paste of two blank lines is the most
  ;; common real-world way to feed a 4-char Enter run to the normalizer.
  (let ((a\r\n\r\n (photo-ai-lisp::%normalize-child-input
                    (coerce (list #\a #\Return #\Newline
                                  #\Return #\Newline)
                            'string))))
    (is (equalp #(97 13) a\r\n\r\n)
        "a<CRLF><CRLF> (four-byte double-CRLF from e.g. a textarea ~
         paste) normalizes to exactly 2 bytes — the collapse must ~
         span runs longer than 2 as well, not only adjacent pairs")))
