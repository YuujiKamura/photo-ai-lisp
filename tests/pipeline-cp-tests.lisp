(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; ACCEPTANCE SPEC for src/pipeline-cp.lisp

(test pipeline-invoke-via-cp-interaction
  "Test that invoke-via-cp actually sends an INPUT and polls TAIL until DONE."
  (let ((input-called nil)
        (tail-count 0))
    ;; We use flet to locally override the CP client functions for this test
    (flet ((photo-ai-lisp:cp-input (c text &key session-id)
             (declare (ignore c session-id))
             (setf input-called t)
             (is (search "/run :scan" text))
             (list "OK" "QUEUED"))
           (photo-ai-lisp:cp-tail (c &key n session-id)
             (declare (ignore c n session-id))
             (incf tail-count)
             (if (< tail-count 3)
                 (list "TAIL" "ghostty-web" "1" "still running...")
                 (list "TAIL" "ghostty-web" "1" "DONE|:scan|(:count 10)"))))
      (multiple-value-bind (out success)
          (photo-ai-lisp:invoke-via-cp :mock-client :scan :input '(:dir "/tmp"))
        (is-true input-called "cp-input should have been called")
        (is (= 3 tail-count) "cp-tail should have been called 3 times until DONE")
        (is (equal '(:count 10) out))
        (is-true success)))))
