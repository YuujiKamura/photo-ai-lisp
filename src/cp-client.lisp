(in-package #:photo-ai-lisp)

;;; Issue #17 — CP (Control Plane) Client implementation.
;;; Provides high-level WebSocket communication with the CP server.

(defclass cp-client ()
  ((driver :accessor cp-client-driver :initarg :driver)
   (last-response :accessor cp-client-last-response :initform nil)
   (response-lock :accessor cp-client-response-lock :initform (bt:make-lock "cp-response-lock"))
   (response-cond :accessor cp-client-response-cond :initform (bt:make-condition-variable :name "cp-response-cond"))))

(defun connect-cp (&key (host "localhost") (port 8080))
  "Connect to the CP WebSocket endpoint at ws://<host>:<port>/ws.
   Returns a client object."
  (let* ((url (format nil "ws://~A:~D/ws" host port))
         (driver (wsd:make-client url))
         (client (make-instance 'cp-client :driver driver)))
    (wsd:on :message driver
            (lambda (message)
              (bt:with-lock-held ((cp-client-response-lock client))
                (setf (cp-client-last-response client) message)
                (bt:condition-notify (cp-client-response-cond client)))))
    (handler-case
        (wsd:start-connection driver)
      (error (c)
        (warn "CP connection failed: ~A" c)))
    client))

(defun disconnect-cp (client)
  "Closes the CP connection."
  (when (and client (not (eq client :mock-client)))
    (wsd:close-connection (cp-client-driver client))))

(defun send-cp-command (client command-string)
  "Sends COMMAND-STRING to the CP server and returns the parsed response list.
   Synchronous."
  (if (eq client :mock-client)
      (list "OK" "MOCK")
      (bt:with-lock-held ((cp-client-response-lock client))
        (setf (cp-client-last-response client) nil)
        (wsd:send (cp-client-driver client) command-string)
        (bt:condition-wait (cp-client-response-cond client)
                           (cp-client-response-lock client))
        (if (cp-client-last-response client)
            (cp-parse-response (cp-client-last-response client))
            (list "ERR" "NO_RESPONSE")))))

(defun wait-for-completion (client session-id &key (timeout 50) (interval 1))
  "Poll state until session becomes idle. Returns t on completion, nil on timeout."
  (loop repeat timeout
        for resp = (send-cp-command client (make-cp-state session-id))
        when (and (listp resp) (getf resp :ok) (string= (getf resp :status) "idle"))
          return t
        do (sleep interval)
        finally (return nil)))

(defun cp-tail (client &key (n 20) session-id)
  "Helper for TAIL command."
  (send-cp-command client (make-cp-tail :n n :session-id session-id)))

(defun cp-input (client text &key session-id)
  "Helper for INPUT command."
  (send-cp-command client (make-cp-input text :session-id session-id)))
