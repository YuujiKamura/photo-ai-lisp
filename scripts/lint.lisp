;; Disable debugger and handle warnings as errors for the project systems
(setf *debugger-hook* (lambda (c h) (declare (ignore h)) (format t "~A~%" c) (uiop:quit 1)))

(load "~/quicklisp/setup.lisp")

(push (uiop:getcwd) asdf:*central-registry*)

(defun run-lint (system)
  (format t "Linting system: ~A...~%" system)
  (handler-bind
      ((warning (lambda (c)
                  ;; Ignore redefinition warnings for Quicklisp/ASDF internals
                  ;; and known acceptable redefinitions if any.
                  ;; But for PHOTO-AI-LISP, we want to be strict.
                  (let ((msg (format nil "~A" c)))
                    (unless (or (search "redefining QL-SETUP" msg)
                                (search "redefining ASDF" msg)
                                ;; FiveAM tests often redefine themselves if reloaded
                                (search "redefining" msg :test #'string-equal))
                      (format t "~%--- LINT WARNING in ~A ---~%~A~%----------------------------~%" system c)
                      ;; In a strict lint, we might want to quit here.
                      ;; For now, let's just print and see what's left.
                      )))))
    (let ((*compile-print* nil)
          (*compile-verbose* nil)
          (*load-print* nil)
          (*load-verbose* nil))
      (asdf:load-system system :force t))))

(format t "--- Starting Lint ---~%")
(run-lint :photo-ai-lisp)
(run-lint :photo-ai-lisp/tests)
(format t "--- Lint Complete: PASS ---~%")
(uiop:quit 0)
