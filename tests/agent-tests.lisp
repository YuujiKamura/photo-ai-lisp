(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; UT4 — unit tests for src/agent.lisp pure helpers.
;;; All tests bind *agent-process* to nil so no subprocess is spawned.
;;; These are state/contract tests only; actual agent invocation is
;;; covered by tests/agent-scenario.lisp.

;; UT4a: agent-alive-p returns nil when *agent-process* is nil.
(test agent-alive-p-nil-with-no-process
  (let ((photo-ai-lisp::*agent-process* nil))
    (is (null (photo-ai-lisp::agent-alive-p))
        "agent-alive-p should return nil when *agent-process* is nil")))

;; UT4b: agent-stdin returns nil when *agent-process* is nil.
(test agent-stdin-nil-with-no-process
  (let ((photo-ai-lisp::*agent-process* nil))
    (is (null (photo-ai-lisp::agent-stdin))
        "agent-stdin should return nil when *agent-process* is nil")))

;; UT4c: agent-stdout returns nil when *agent-process* is nil.
(test agent-stdout-nil-with-no-process
  (let ((photo-ai-lisp::*agent-process* nil))
    (is (null (photo-ai-lisp::agent-stdout))
        "agent-stdout should return nil when *agent-process* is nil")))

;; UT4d: stop-agent does not error when *agent-process* is nil (idempotent).
(test agent-stop-agent-idempotent-with-nil
  (let ((photo-ai-lisp::*agent-process* nil))
    (finishes (photo-ai-lisp::stop-agent))
    (is (null photo-ai-lisp::*agent-process*)
        "stop-agent should leave *agent-process* nil when called on nil")))

;; UT4e: agent-send returns empty string when no agent process is live.
(test agent-send-returns-empty-string-with-no-process
  (let ((photo-ai-lisp::*agent-process* nil))
    (let ((result (photo-ai-lisp::agent-send "test prompt")))
      (is (stringp result)
          "agent-send should return a string, got: ~s" (type-of result))
      (is (string= "" result)
          "agent-send should return empty string when *agent-process* is nil, got: ~s"
          result))))

;; UT4f: *agent-command* defvar is a string.
(test agent-command-var-is-string
  (is-true (stringp photo-ai-lisp::*agent-command*)
           "*agent-command* should be a string, got: ~s"
           (type-of photo-ai-lisp::*agent-command*)))

;; UT4g: *agent-args* defvar is a list.
(test agent-args-var-is-list
  (is-true (listp photo-ai-lisp::*agent-args*)
           "*agent-args* should be a list, got: ~s"
           (type-of photo-ai-lisp::*agent-args*)))

;; UT4h: *agent-process* defvar is bound (initially nil).
(test agent-process-defvar-bound
  (is-true (boundp 'photo-ai-lisp::*agent-process*)
           "*agent-process* defvar should be bound"))
