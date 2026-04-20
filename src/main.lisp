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

(hunchentoot:define-easy-handler (shell-trace-page :uri "/api/shell-trace") ()
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (shell-trace-handler))

(hunchentoot:define-easy-handler (reload-page :uri "/api/reload") ()
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (let ((module (hunchentoot:get-parameter "module")))
    (reload-handler module)))

(hunchentoot:define-easy-handler (inject-page :uri "/api/inject") ()
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (let ((text (hunchentoot:get-parameter "text")))
    (inject-handler text)))

(hunchentoot:define-easy-handler (eval-page :uri "/api/eval") ()
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (live-eval-handler hunchentoot:*request*))

(defun case-view-handler-wrapper ()
  (let* ((uri (hunchentoot:request-uri hunchentoot:*request*))
         (id  (subseq uri 7)))
    (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
    (case-view-handler id)))

(defvar *vendor-mime-types*
  '(("wasm" . "application/wasm")
    ("js"   . "application/javascript; charset=utf-8")
    ("css"  . "text/css; charset=utf-8")
    ("map"  . "application/json; charset=utf-8"))
  "Ext -> Content-Type for assets under /vendor/. Hunchentoot's stock
   folder-dispatcher falls back to application/octet-stream for .wasm,
   which the browser refuses for streaming instantiation.")

(defun %vendor-content-type (pathname)
  (let* ((ext (or (pathname-type pathname) ""))
         (mime (cdr (assoc ext *vendor-mime-types* :test #'string-equal))))
    (or mime "application/octet-stream")))

(defun vendor-handler ()
  "Serve files under static/vendor/ with correct MIME types.
   Needed because ghostty-web.wasm must be delivered as application/wasm
   for WebAssembly.instantiateStreaming. Blocks path traversal."
  (let* ((uri       (hunchentoot:script-name hunchentoot:*request*))
         (rel       (subseq uri (length "/vendor/")))
         (safe-rel  (remove-if (lambda (c) (char= c #\\)) rel))
         (root      (merge-pathnames "static/vendor/" (uiop:getcwd)))
         (path      (merge-pathnames safe-rel root))
         (truename  (ignore-errors (uiop:truename* path)))
         (root-true (uiop:truename* root)))
    (cond
      ((or (null truename)
           (search ".." safe-rel)
           (not (uiop:subpathp truename root-true)))
       (setf (hunchentoot:return-code*) 404)
       "not found")
      (t
       (setf (hunchentoot:content-type*) (%vendor-content-type truename))
       (hunchentoot:handle-static-file truename
                                       (%vendor-content-type truename))))))

(defun start (&key (port 8090))
  (unless *acceptor*
    (setf *acceptor*
          (make-instance 'ws-easy-acceptor :port port))
    ;; Prefix dispatcher for /cases/<id>
    (pushnew (hunchentoot:create-prefix-dispatcher "/cases/" 'case-view-handler-wrapper)
             hunchentoot:*dispatch-table*)
    ;; Prefix dispatcher for /vendor/ (ghostty-web bundle etc.).
    (pushnew (hunchentoot:create-prefix-dispatcher "/vendor/" 'vendor-handler)
             hunchentoot:*dispatch-table*)
    (hunchentoot:start *acceptor*))
  *acceptor*)

(defun stop ()
  (when *acceptor*
    (hunchentoot:stop *acceptor*)
    (setf *acceptor* nil)))
