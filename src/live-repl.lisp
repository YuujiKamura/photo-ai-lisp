(in-package #:photo-ai-lisp)

;;; Live REPL over HTTP. POST an S-expression to /api/eval and it is
;;; read + evaluated in the photo-ai-lisp package of the running image,
;;; and the printed result is returned as JSON. Gated to 127.0.0.1.
;;;
;;; This turns the server into its own DSL host: curl callers can
;;; redefine any function, add new endpoints, inspect internals, or
;;; hot-patch behavior — without SLIME, without Swank, without
;;; restart. The kind of 'should not be possible' trick Lisp's
;;; code-is-data property makes trivial.

(defvar *live-repl-enabled*
  (not (equal (uiop:getenv "DISABLE_LIVE_REPL") "1"))
  "If true, /api/eval accepts arbitrary S-expressions from localhost.
   Disable with DISABLE_LIVE_REPL=1 when exposing the server beyond 127.0.0.1.")

(defun %localhost-p (request)
  "Narrow guard: only allow /api/eval from loopback."
  (let ((addr (hunchentoot:remote-addr request)))
    (or (equal addr "127.0.0.1")
        (equal addr "::1"))))

(defun %render-value (v)
  "Render V for JSON. Uses prin1-to-string so the client can read it
   back as an S-expression if they want."
  (prin1-to-string v))

(defun live-eval (source)
  "Read SOURCE (a string), eval it in the :photo-ai-lisp package,
   return (:ok VALUE-STRING) or (:error MESSAGE)."
  (handler-case
      (let* ((*package* (find-package :photo-ai-lisp))
             (form (read-from-string source))
             (value (eval form)))
        (list :ok (%render-value value)))
    (error (e)
      (list :error (princ-to-string e)))))

(defun live-eval-handler (request)
  "HTTP handler body for POST /api/eval. Body is treated as a Lisp
   S-expression. Responds with {ok,value} or {ok:false,error}."
  (unless *live-repl-enabled*
    (return-from live-eval-handler
      (format nil "{\"ok\":false,\"error\":\"live-repl disabled\"}")))
  (unless (%localhost-p request)
    (return-from live-eval-handler
      (format nil "{\"ok\":false,\"error\":\"localhost only\"}")))
  (let* ((body (or (hunchentoot:raw-post-data
                    :request request :force-text t)
                   (hunchentoot:get-parameter "form" request)
                   "")))
    (when (or (null body) (zerop (length body)))
      (return-from live-eval-handler
        (format nil "{\"ok\":false,\"error\":\"empty form\"}")))
    (let ((r (live-eval body)))
      (if (getf r :ok)
          (format nil "{\"ok\":true,\"value\":~s}"
                  (getf r :ok))
          (format nil "{\"ok\":false,\"error\":~s}"
                  (getf r :error))))))
