(defpackage #:photo-ai-lisp/tests
  (:use #:cl #:fiveam)
  (:export #:run-tests))

(in-package #:photo-ai-lisp/tests)

(def-suite photo-ai-lisp-tests
  :description "photo-ai-lisp scenario tests")

(defun run-tests ()
  (let ((results (run 'photo-ai-lisp-tests)))
    (explain! results)
    (unless (results-status results)
      (uiop:quit 1))))
