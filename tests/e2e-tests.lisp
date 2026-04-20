(in-package #:photo-ai-lisp/tests)

;;; Team E — browser E2E regression for /shell picker -> Claude REPL.
;;;
;;; Scope: this suite owns exactly one test, `picker-to-claude-e2e`.
;;; It shells out to tests/e2e/picker-to-claude.mjs (Node + puppeteer-core)
;;; which drives headless Chrome through the full stack fixed in de778f7
;;; / e5a19b7 / 2a95c96. Detection is via /api/shell-trace, not canvas
;;; scraping — see tests/e2e/README.md for the stack diagram.
;;;
;;; Graceful degradation: if any of {node, puppeteer-core, Chrome, claude}
;;; is missing, the test reports a fiveam skip (5am:skip) with a reason
;;; string rather than failing. This keeps the suite green on boxes that
;;; lack the browser toolchain while still blocking regressions on the
;;; dev workstation where the full stack is available.

(5am:def-suite e2e-suite :description "browser-driven /shell E2E regression")
(5am:in-suite e2e-suite)

(defun %e2e-repo-root ()
  "Absolute pathname of the repo root, derived from *load-truename*.
   tests/e2e-tests.lisp lives directly under tests/, so one directory up
   is the repo root. Avoids hard-coding paths like C:/Users/... which
   would break every agent that is not the original author."
  (let* ((here (or *load-truename* *compile-file-truename*
                   (merge-pathnames "tests/e2e-tests.lisp" (uiop:getcwd))))
         (dir  (pathname-directory here)))
    (make-pathname :defaults here
                   :name nil :type nil :version nil
                   :directory (butlast dir))))

(defun %e2e-harness-path ()
  (namestring
   (merge-pathnames "tests/e2e/picker-to-claude.mjs" (%e2e-repo-root))))

(defun %which (cmd)
  "Return the resolved path of CMD on $PATH, or NIL if not found.
   Uses `where` on Windows and `command -v` elsewhere — both are POSIX
   or Windows builtins, no extra deps."
  (handler-case
      (let ((out (uiop:run-program
                  (if (uiop:os-windows-p)
                      (list "where" cmd)
                      (list "sh" "-c" (format nil "command -v ~a" cmd)))
                  :output :string
                  :error-output nil
                  :ignore-error-status t)))
        (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) out)))
          (when (plusp (length trimmed))
            ;; `where` prints one path per line; take the first.
            (let ((nl (position #\Newline trimmed)))
              (if nl (subseq trimmed 0 nl) trimmed)))))
    (error () nil)))

(defun %chrome-present-p ()
  (or (let ((env (uiop:getenv "PAI_E2E_CHROME")))
        (and env (probe-file env)))
      (some #'probe-file
            '("C:/Program Files/Google/Chrome/Application/chrome.exe"
              "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe"
              "/usr/bin/google-chrome"
              "/usr/bin/chromium"
              "/usr/bin/chromium-browser"
              "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"))))

(defun %puppeteer-core-present-p ()
  (let ((root (%e2e-repo-root)))
    (or (probe-file (merge-pathnames
                     "tests/e2e/node_modules/puppeteer-core/package.json" root))
        (probe-file (merge-pathnames
                     "demo/node_modules/puppeteer-core/package.json" root)))))

(defun %pick-e2e-port ()
  "PAI_E2E_PORT env wins if set and parseable; otherwise pick a random
   port in 9000–9899 (same band as inject-e2e-scenario) so parallel
   runs do not clobber each other."
  (let ((env (uiop:getenv "PAI_E2E_PORT")))
    (or (and env (ignore-errors (parse-integer env :junk-allowed t)))
        (+ 9000 (random 900)))))

(defun %harness-skip-reason ()
  "Return a short string explaining why the harness should be skipped,
   or NIL if every prerequisite is satisfied. Centralising this keeps
   the skip messages consistent between the test body and the report."
  (cond
    ((equal (uiop:getenv "PAI_E2E_SKIP") "1")
     "env PAI_E2E_SKIP=1")
    ((not (probe-file (%e2e-harness-path)))
     (format nil "harness missing: ~a" (%e2e-harness-path)))
    ((not (%which "node"))
     "node not on PATH")
    ((not (%which "claude"))
     "claude CLI not on PATH")
    ((not (%chrome-present-p))
     "chrome not found (set PAI_E2E_CHROME to override)")
    ((not (%puppeteer-core-present-p))
     "puppeteer-core not installed (cd tests/e2e && npm install)")
    (t nil)))

(defun %run-harness (port)
  "Invoke the node harness against PORT. Returns (VALUES STDOUT STDERR
   EXIT-CODE). Never throws — on internal failure returns a synthetic
   FAIL line so the caller's parsing stays simple."
  (handler-case
      (multiple-value-bind (stdout stderr exit)
          (uiop:run-program
           (list (or (%which "node") "node")
                 (%e2e-harness-path)
                 "--port" (princ-to-string port))
           :output :string
           :error-output :string
           :ignore-error-status t)
        (values (or stdout "") (or stderr "") exit))
    (error (e)
      (values (format nil "FAIL harness-spawn-error~%")
              (format nil "~a" e)
              3))))

(defun %first-line (s)
  (if (stringp s)
      (let ((nl (position #\Newline s)))
        (string-trim '(#\Space #\Tab #\Return)
                     (if nl (subseq s 0 nl) s)))
      ""))

(defun %run-picker-to-claude-e2e ()
  "Full browser round-trip: /shell page -> picker auto-inject ->
   user keystroke '1' + Enter -> claude CLI boots -> its banner
   appears in /api/shell-trace. Skips gracefully when any of the
   heavy deps (node, puppeteer-core, Chrome, claude CLI) is absent.

   Split out of the 5am:test body because 5am does not wrap the body
   in a block named after the test, so RETURN-FROM against the test
   name fails to compile. A plain DEFUN gives us a real block to
   early-exit from on the skip path."
  (let ((skip (%harness-skip-reason)))
    (when skip
      (5am:skip "e2e harness skipped: ~a" skip)
      (return-from %run-picker-to-claude-e2e)))
  (let ((port (%pick-e2e-port))
        (started-p nil))
    (unwind-protect
         (progn
           ;; 1. Start the Lisp server in-process. demo.sh hard-codes
           ;;    8090 and the Team E brief forbids editing it, so we
           ;;    mirror the pattern established by inject-e2e-scenario.lisp
           ;;    instead. The harness sees the same HTTP surface either way.
           (photo-ai-lisp:start :port port)
           (setf started-p t)
           (sleep 0.5)
           ;; 2. Clear the trace ring so we only look at bytes produced
           ;;    by THIS run's picker -> claude flow, not leftovers from
           ;;    an earlier shell-trace-tests suite in the same image.
           (photo-ai-lisp::shell-trace-clear)
           ;; 3. Run the node harness. Its stdout contract is one line:
           ;;    PASS | FAIL <reason> | SKIP <reason>.
           (multiple-value-bind (stdout stderr exit)
               (%run-harness port)
             (let ((verdict (%first-line stdout)))
               (cond
                 ((or (string= verdict "PASS") (= exit 0))
                  (5am:is-true t
                               "PASS on port ~a (exit=~a)" port exit))
                 ((or (= exit 2)
                      (and (>= (length verdict) 4)
                           (string= (subseq verdict 0 4) "SKIP")))
                  (5am:skip "harness reported: ~a" verdict))
                 (t
                  (5am:is (string= verdict "PASS")
                          "harness verdict=~s exit=~a~%stderr=~a"
                          verdict exit
                          (subseq stderr 0 (min 2000 (length stderr)))))))))
      ;; 4. Always stop the server so a later test can rebind the port.
      (when started-p
        (ignore-errors (photo-ai-lisp:stop)))
      (sleep 0.2))))

(5am:test picker-to-claude-e2e
  "Thin wrapper around %RUN-PICKER-TO-CLAUDE-E2E. Kept trivial so the
   fiveam description stays readable in test output while the
   implementation lives in a normal defun (see that function's
   docstring for the RETURN-FROM / 5am:skip interaction)."
  (%run-picker-to-claude-e2e))
