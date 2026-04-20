;;;; src/control.lisp
;;;; Server-to-browser live-reload channel (Observer pattern).
;;;;
;;;; /ws/control is a push-only WebSocket. Clients register on connect
;;;; and receive short text frames like "reload:term" so the UI can
;;;; hot-swap the affected surface without a full page refresh.
;;;;
;;;; Kept separate from term.lisp so shell / PTY plumbing stays focused
;;;; on terminal sessions, and separate from presets.lisp so any
;;;; lifecycle event (not just hot-reload) can publish without a cycle.

(in-package #:photo-ai-lisp)

(defclass control-client (hunchensocket:websocket-client) ())

(defclass control-resource (hunchensocket:websocket-resource)
  ()
  (:default-initargs :client-class 'control-client))

(defvar *control-resource* (make-instance 'control-resource))
(defvar *control-clients* '())
(defvar *control-clients-lock* (bordeaux-threads:make-lock "control-clients"))

(defmethod hunchensocket:client-connected ((r control-resource) (c control-client))
  (bordeaux-threads:with-lock-held (*control-clients-lock*)
    (pushnew c *control-clients*)))

(defmethod hunchensocket:client-disconnected ((r control-resource) (c control-client))
  (bordeaux-threads:with-lock-held (*control-clients-lock*)
    (setf *control-clients* (remove c *control-clients*))))

(defun control-broadcast (text)
  "Push TEXT to every connected /ws/control client. Returns the count.
   Dead sockets are tolerated — per-socket send errors are swallowed
   since client-disconnected will clean them up."
  (let ((recipients (bordeaux-threads:with-lock-held (*control-clients-lock*)
                      (copy-list *control-clients*))))
    (loop for c in recipients
          count (handler-case
                    (progn (hunchensocket:send-text-message c text) t)
                  (error () nil)))))

(defun %find-control-resource (request)
  (when (string= "/ws/control" (hunchentoot:script-name request))
    *control-resource*))

(pushnew '%find-control-resource hunchensocket:*websocket-dispatch-table*)

;; Subscribe to reload events. The reload layer (presets.lisp) owns the
;; event source; we attach ourselves as an observer so presets has no
;; direct knowledge of the WebSocket transport. pushnew keeps repeat
;; loads of control.lisp from multiplying the subscription.
(pushnew #'control-broadcast *reload-observers*)
