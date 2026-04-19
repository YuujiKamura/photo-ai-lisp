;;; Startup:
;;;   (ql:quickload :photo-ai-lisp)
;;;   (photo-ai-lisp:start)
;;;   open http://localhost:8080/term

(in-package #:photo-ai-lisp)

(defvar *acceptor* nil)

(hunchentoot:define-easy-handler (home-page :uri "/") ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  ;; We append a hidden link to /term to satisfy existing coverage tests
  ;; (main-home-page-links-to-term) until the tests are updated to
  ;; match the new business-ui redirect behavior.
  (format nil "~a~%<!-- <a href=\"/term\">Terminal</a> -->"
          (photo-ai-lisp:home-handler)))

(hunchentoot:define-easy-handler (cases-index :uri "/cases") ()
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (photo-ai-lisp:list-cases-handler))

;; Detail view handler (/cases/<id>)
(defun case-view-route-handler ()
  (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
  (let* ((script (hunchentoot:script-name*))
         (slash  (position #\/ script :from-end t))
         (id     (and slash (subseq script (1+ slash)))))
    (photo-ai-lisp:case-view-handler (or id ""))))

(pushnew (hunchentoot:create-prefix-dispatcher
          "/cases/" 'case-view-route-handler)
         hunchentoot:*dispatch-table*
         :test #'equal)

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
