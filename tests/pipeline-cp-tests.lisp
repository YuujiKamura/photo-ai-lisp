(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; ACCEPTANCE SPEC for src/pipeline-cp.lisp

(defmacro with-mocked-cp ((&rest bindings) &body body)
  "Temporarily replace symbol-function of each BINDING (name . lambda-form)
   for the duration of BODY, restoring originals in an UNWIND-PROTECT.
   Unlike FLET with package-qualified names, this actually intercepts calls
   made from code outside the form's lexical scope (e.g. from INVOKE-VIA-CP)."
  (let ((orig-syms (loop for b in bindings collect (gensym "ORIG"))))
    `(let ,(loop for (name . nil) in bindings
                 for g in orig-syms
                 collect `(,g (symbol-function ',name)))
       (unwind-protect
            (progn
              ,@(loop for (name . lam) in bindings
                      collect `(setf (symbol-function ',name) ,(car lam)))
              ,@body)
         ,@(loop for (name . nil) in bindings
                 for g in orig-syms
                 collect `(setf (symbol-function ',name) ,g))))))

(test pipeline-invoke-via-cp-json
  "Test that invoke-via-cp works in JSON mode (waiting for idle)."
  (let ((input-called nil)
        (wait-called nil))
    (with-mocked-cp
        ((photo-ai-lisp:cp-input
          (lambda (c text &key session-id)
            (declare (ignore c session-id text))
            (setf input-called t)
            (list :ok t :status "active")))
         (photo-ai-lisp:wait-for-completion
          (lambda (c sess &key timeout interval)
            (declare (ignore c sess timeout interval))
            (setf wait-called t)
            t)))
      (multiple-value-bind (out success)
          (photo-ai-lisp:invoke-via-cp :mock-client :scan :input '(:dir "/tmp"))
        (is-true input-called "cp-input should have been called")
        (is-true wait-called "wait-for-completion should have been called")
        (is-true success)
        (is (null out))))))

(test pipeline-invoke-via-cp-interaction
  "Test that invoke-via-cp actually sends an INPUT and polls TAIL until DONE."
  (let ((input-called nil)
        (tail-count 0))
    (with-mocked-cp
        ((photo-ai-lisp:cp-input
          (lambda (c text &key session-id)
            (declare (ignore c session-id))
            (setf input-called t)
            ;; invoke-via-cp builds the command via (format nil "/run ~A ~S" ...)
            ;; so :scan prints as SCAN under the default upcase readtable.
            (is (search "/run SCAN" text))
            ;; Return a non-plist list -> invoke-via-cp takes legacy path.
            (list "OK" "QUEUED")))
         (photo-ai-lisp:cp-tail
          (lambda (c &key n session-id)
            (declare (ignore c n session-id))
            (incf tail-count)
            (if (< tail-count 3)
                (list "TAIL" "ghostty-web" "1" "still running...")
                ;; invoke-via-cp searches for (format nil "DONE|~A|" :scan)
                ;; which prints as "DONE|SCAN|" under the default readtable.
                (list "TAIL" "ghostty-web" "1" "DONE|SCAN|(:count 10)")))))
      (multiple-value-bind (out success)
          (photo-ai-lisp:invoke-via-cp :mock-client :scan :input '(:dir "/tmp"))
        (is-true input-called "cp-input should have been called")
        (is (= 3 tail-count) "cp-tail should have been called 3 times until DONE")
        (is (equal '(:count 10) out))
        (is-true success)))))
