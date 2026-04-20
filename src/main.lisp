;;; Startup:
;;;   (ql:quickload :photo-ai-lisp)
;;;   (photo-ai-lisp:start :port 8090)
;;;   open http://localhost:8090/

(in-package #:photo-ai-lisp)

(defvar *acceptor* nil)

(hunchentoot:define-easy-handler (home-page :uri "/") ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (home-handler))

(hunchentoot:define-easy-handler (cases-list-page :uri "/cases") ()
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (list-cases-handler))

(hunchentoot:define-easy-handler (masters-list-page :uri "/api/masters") ()
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (list-masters-handler))

(hunchentoot:define-easy-handler (presets-list-page :uri "/api/presets") ()
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (list-presets-handler))

(defun run-preset-handler-wrapper ()
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (name (subseq uri (length "/api/run/"))))
    (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
    (run-preset-handler name)))

(defun case-view-handler-wrapper ()
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (id  (subseq uri 7)))
    (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
    (case-view-handler id)))

(defun start (&key (port 8090))
  (unless *acceptor*
    (setf *acceptor*
          (make-instance 'hunchentoot:easy-acceptor :port port))
    ;; Prefix dispatcher for /cases/<id>
    (pushnew (hunchentoot:create-prefix-dispatcher "/cases/" 'case-view-handler-wrapper)
             hunchentoot:*dispatch-table*)
    ;; Prefix dispatcher for /api/run/<name>
    (pushnew (hunchentoot:create-prefix-dispatcher "/api/run/" 'run-preset-handler-wrapper)
             hunchentoot:*dispatch-table*)
    (hunchentoot:start *acceptor*))
  *acceptor*)

(defun stop ()
  (when *acceptor*
    (hunchentoot:stop *acceptor*)
    (setf *acceptor* nil)))
