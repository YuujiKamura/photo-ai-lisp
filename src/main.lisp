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

;; hunchentoot:define-easy-handler has no :uri-prefix option — only :uri.
;; We register a prefix dispatcher into *dispatch-table* explicitly so
;; /api/session/<id> routes to the handler regardless of trailing segment.
(defun api-session-route-handler ()
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (let* ((script-name (hunchentoot:script-name*))
         (prefix "/api/session/")
         (session-id (if (and (>= (length script-name) (length prefix))
                              (string= prefix script-name
                                       :end2 (length prefix)))
                         (subseq script-name (length prefix))
                         "")))
    (if (zerop (length session-id))
        "{\"error\":\"not-found\",\"id\":\"\"}"
        (photo-ai-lisp:api-session-handler session-id))))

(pushnew (hunchentoot:create-prefix-dispatcher
          "/api/session/" 'api-session-route-handler)
         hunchentoot:*dispatch-table*
         :test #'equal)

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
