;;; Startup:
;;;   (ql:quickload :photo-ai-lisp)
;;;   (photo-ai-lisp:start)

(in-package #:photo-ai-lisp)

(defvar *acceptor* nil)

(define-easy-handler (home :uri "/") ()
  (with-html-output-to-string (out nil :prologue t)
    (:html
     (:head
      (:title "photo-ai-lisp"))
     (:body
      (:h1 "hello from photo-ai-lisp")
      (:p "skeleton")))))

(defun start (&key (port 8080))
  (unless *acceptor*
    (setf *acceptor* (make-instance 'easy-acceptor :port port))
    (start *acceptor*))
  *acceptor*)

(defun stop ()
  (when *acceptor*
    (stop *acceptor*)
    (setf *acceptor* nil)))
