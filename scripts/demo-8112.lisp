;;;; scripts/demo-8112.lisp
;;;; Port-8112 variant of demo-8091.lisp. Same dynamic-path pattern —
;;;; no hardcoded repo location, so the script is portable across
;;;; clones. Resolves repo-top from *load-truename* so `sbcl --script
;;;; scripts/demo-8112.lisp` works from any cwd.

(load "~/quicklisp/setup.lisp")

(defvar *repo-root*
  (make-pathname :defaults (or *load-truename* *load-pathname*)
                 :name nil :type nil :version nil))

(defvar *repo-top*
  (make-pathname :defaults *repo-root*
                 :directory (butlast (pathname-directory *repo-root*))))

(push *repo-top* asdf:*central-registry*)

(handler-case
    (progn
      (asdf:clear-system :photo-ai-lisp)
      (ql:quickload :photo-ai-lisp :silent t)
      (uiop:symbol-call :photo-ai-lisp :start :port 8112)
      (format t "SERVER http://localhost:8112/~%")
      (finish-output)
      (loop (sleep 60)))
  (error (c)
    (format *error-output* "FATAL: ~a~%" c)
    (sb-ext:exit :code 1)))
