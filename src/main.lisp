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

;; /api/presets and /api/presets/<name> are routed through the method
;; dispatcher in presets.lisp (GET / NEW / REWRITE / DELETE / DEPLOY).
;; The prefix dispatcher is registered in START; no easy-handler here.

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

(defun %cases-dispatch-wrapper ()
  "Single dispatcher for all /cases/* requests.
   POST .../input  → case-input-handler-wrapper (returns JSON)
   GET  anything   → case-view-handler-wrapper  (returns HTML)"
  (let* ((uri    (hunchentoot:request-uri hunchentoot:*request*))
         (method (hunchentoot:request-method hunchentoot:*request*)))
    (if (and (eq method :post)
             (search "/input" uri))
        ;; POST /cases/<id>/input
        (let* ((without-prefix (subseq uri 7))      ; strip "/cases/"
               (end (search "/input" without-prefix))
               (id  (if end
                        (subseq without-prefix 0 end)
                        without-prefix))
               (cmd (or (hunchentoot:post-parameter "cmd") "")))
          (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
          (let ((body (input-bridge-handler id cmd)))
            ;; T2.h pivot: demo mode and legacy CP mode both route through
            ;; input-bridge-handler now. An "error" substring in the body
            ;; is the single signal that the send could not be delivered
            ;; (legacy: *demo-session-id* nil; demo: no /ws/shell open).
            (when (search "\"error\"" body)
              (setf (hunchentoot:return-code*) 503))
            body))
        ;; GET /cases/<id>
        (let ((id (subseq uri 7)))
          (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
          (case-view-handler id)))))

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
    ;; Prefix dispatcher for /cases/* (GET view + POST input, branched internally)
    (pushnew (hunchentoot:create-prefix-dispatcher "/cases/" '%cases-dispatch-wrapper)
             hunchentoot:*dispatch-table*)
    ;; Prefix dispatcher for /api/presets[/<name>] — branches on HTTP method
    ;; (GET / NEW / REWRITE / DELETE / DEPLOY) inside %presets-dispatch.
    (pushnew (hunchentoot:create-prefix-dispatcher "/api/presets" '%presets-dispatch)
             hunchentoot:*dispatch-table*)
    ;; Prefix dispatcher for /vendor/ (ghostty-web bundle etc.).
    (pushnew (hunchentoot:create-prefix-dispatcher "/vendor/" 'vendor-handler)
             hunchentoot:*dispatch-table*)
    (hunchentoot:start *acceptor*))
  *acceptor*)

(defun stop ()
  (when *acceptor*
    ;; Step 1: close every /ws/shell client and kill child processes FIRST.
    ;; On Windows the AFD layer holds sockets in CLOSE_WAIT until the server
    ;; explicitly closes its side. Without this, 40+ CLOSE_WAIT sockets
    ;; accumulate under Chrome's auto-reconnect loop and block rebind on the
    ;; same port. See GitHub issue #31.
    (let ((n (ignore-errors (close-shell-clients))))
      (when (and n (plusp n))
        ;; Give Chrome time to acknowledge the WS close frame so the TCP
        ;; handshake completes. 200ms is sufficient on localhost; the sockets
        ;; have already received FIN from the close call above regardless.
        (sleep 0.2)))
    ;; Step 2: stop the acceptor (closes the listen socket).
    (hunchentoot:stop *acceptor*)
    (setf *acceptor* nil)))
