(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;; Fake agent: echo whatever we send on stdin straight back on stdout.
;; `cat` is available on every CI target (ubuntu-latest) and on Windows dev
;; machines via Git Bash — if it is not on PATH we cannot exercise this
;; lifecycle test deterministically, so we skip.
(defun fake-agent-spec () '("cat" . ()))

(defun cat-available-p ()
  (handler-case
      (progn (uiop:run-program '("cat" "--version") :output nil :error-output nil)
             t)
    (error () nil)))

(defmacro with-fake-agent (() &body body)
  `(let ((photo-ai-lisp::*agent-command* (car (fake-agent-spec)))
         (photo-ai-lisp::*agent-args*    (cdr (fake-agent-spec))))
     (unwind-protect
          (progn ,@body)
       (ignore-errors (photo-ai-lisp::stop-agent)))))

(test agent-start-reports-alive
  (if (not (cat-available-p))
      (skip "cat not on PATH; skipping agent lifecycle test")
      (with-fake-agent ()
        (photo-ai-lisp::start-agent)
        (sleep 0.2)
        (is-true (photo-ai-lisp::agent-alive-p))
        (photo-ai-lisp::stop-agent)
        (is-false (photo-ai-lisp::agent-alive-p)))))

(test agent-restart-cycles
  (if (not (cat-available-p))
      (skip "cat not on PATH; skipping agent lifecycle test")
      (with-fake-agent ()
        (photo-ai-lisp::start-agent)
        (sleep 0.2)
        (is-true (photo-ai-lisp::agent-alive-p))
        (photo-ai-lisp::restart-agent)
        (sleep 0.2)
        (is-true (photo-ai-lisp::agent-alive-p)))))

(test agent-send-round-trips-through-fake
  (if (not (cat-available-p))
      (skip "cat not on PATH; skipping agent round-trip test")
      (with-fake-agent ()
        (photo-ai-lisp::start-agent)
        (sleep 0.2)
        (let ((reply (photo-ai-lisp::agent-send "hello-from-lisp")))
          (is (stringp reply))
          (is (search "hello-from-lisp" reply)
              "fake agent should echo our input back (got: ~S)" reply)))))

(test agent-send-empty-when-not-alive
  ;; No start — agent-send must not signal, just return "".
  (let ((photo-ai-lisp::*agent-process* nil))
    (is (string= "" (photo-ai-lisp::agent-send "ignored")))))
