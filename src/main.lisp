;;; Startup:
;;;   (ql:quickload :photo-ai-lisp)
;;;   (photo-ai-lisp:start)
;;;   open http://localhost:8080/term

(in-package #:photo-ai-lisp)

(defvar *acceptor* nil)

(hunchentoot:define-easy-handler (home-page :uri "/") ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (cl-who:with-html-output-to-string (out nil :prologue t)
    (:html
     (:head (:title "photo-ai-lisp"))
     (:body
      (:h1 "photo-ai-lisp")
      (:p (:a :href "/term" "Open terminal"))))))

(defun start (&key (port 8080))
  (unless *acceptor*
    (setf *acceptor*
          (make-instance 'ws-easy-acceptor :port port))
    (hunchentoot:start *acceptor*))
  *acceptor*)

(defun stop ()
  (when *acceptor*
    (hunchentoot:stop *acceptor*)
    (setf *acceptor* nil)))
