(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; ACCEPTANCE SPEC for src/pipeline-cp.lisp

(test pipeline-invoke-via-cp-returns-values
  "invoke-via-cp should return two values: output plist and success boolean."
  (handler-case
      (let ((client :mock-client))
        (multiple-value-bind (out success)
            (photo-ai-lisp:invoke-via-cp client :scan :input '(:dir "/tmp"))
          (is (listp out))
          (is-true (member success '(t nil)))))
    (photo-ai-lisp::unimplemented ()
      (fail "invoke-via-cp is unimplemented"))))
