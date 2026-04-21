;;;; scripts/demo.lisp
;;;; One-command server launcher for photo-ai-lisp.
;;;; Pushes current repo root to ASDF central registry (the default
;;;; `ql:quickload :photo-ai-lisp` otherwise picks up an old copy such as
;;;; `photo-ai-lisp-track-b`), clears the cached system, loads the current
;;;; source, and starts the Hunchentoot server on port 8090.

(load "~/quicklisp/setup.lisp")

(defvar *repo-root*
  (make-pathname :defaults (or *load-truename* *load-pathname*)
                 :name nil :type nil :version nil))

;; scripts/ lives directly under repo root; demo.lisp sits in scripts/.
(defvar *repo-top*
  (make-pathname :defaults *repo-root*
                 :directory (butlast (pathname-directory *repo-root*))))

(push *repo-top* asdf:*central-registry*)

(handler-case
    (progn
      (asdf:clear-system :photo-ai-lisp)
      (ql:quickload :photo-ai-lisp :silent t)
      (uiop:symbol-call :photo-ai-lisp :start :port 8091)
      (format t "SERVER http://localhost:8091/~%")
      ;; Optional: Swank for SLIME hot-reload workflow.
      ;; Loaded lazily so the default install does not require swank.
      ;; Disable with NO_SWANK=1.
      (unless (equal (uiop:getenv "NO_SWANK") "1")
        (handler-case
            (progn
              (ql:quickload :swank :silent t)
              (funcall (uiop:find-symbol* :create-server :swank)
                       :port 4005 :dont-close t)
              (format t "SWANK localhost:4005 (slime-connect)~%"))
          (error (c)
            (format t "(swank unavailable: ~a)~%" c))))
      (finish-output)

      ;; Install SIGINT handler so Ctrl-C shuts down cleanly.
      ;; Use find-symbol so this file still READs on SBCL builds that
      ;; do not export ENABLE-INTERRUPT/SIGINT.
      #+sbcl
      (let ((enable (find-symbol "ENABLE-INTERRUPT" "SB-SYS"))
            (sigint (find-symbol "SIGINT" "SB-UNIX")))
        (when (and enable sigint)
          (funcall enable sigint
                   (lambda (&rest _)
                     (declare (ignore _))
                     (format t "~%Shutting down...~%")
                     (finish-output)
                     (ignore-errors
                      (uiop:symbol-call :photo-ai-lisp :stop))
                     (uiop:quit 0)))))

      ;; Block forever.
      (loop (sleep 60)))
  (error (c)
    (format *error-output* "ERROR: ~A~%" c)
    (ignore-errors (uiop:symbol-call :photo-ai-lisp :stop))
    (uiop:quit 1)))
