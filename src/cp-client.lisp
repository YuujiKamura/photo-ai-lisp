(in-package #:photo-ai-lisp)

;;; Issue #17 — CP (Control Plane) Client implementation.
;;; Issue #30 Phase 2 (G1.b) — pending-request table keyed by msg_id.
;;;
;;; Provides high-level WebSocket communication with the CP server.  Multiple
;;; callers can issue requests concurrently; each call registers a "waiter"
;;; in *pending-requests* (keyed by the header.msg_id of the frame it sends),
;;; then blocks on that waiter's per-request condition variable until the
;;; matching reply arrives — identified by parent_header.msg_id (preferred)
;;; or header.msg_id (server-echoed fallback until G1.c lands).
;;;
;;; Reply-matching policy for legacy flat replies (no header / parent_header):
;;; positional fallback when exactly one waiter is pending (single-caller
;;; back-compat with pre-G1.b callers), otherwise the reply is dropped onto
;;; the broadcast channel (a log line for now).  See docstring on
;;; %deliver-cp-message for details.
;;;
;;; Concurrency discipline:
;;;   * All pending-table mutations inside (bt:with-lock-held pending-lock).
;;;   * Never hold pending-lock across socket I/O or a condition-wait — drop
;;;     before waiting, reacquire only for cleanup.
;;;   * Each caller gets its own waiter object; waiters are never shared.

;;; --- conditions ---------------------------------------------------------

(define-condition cp-request-timeout (error)
  ((msg-id  :initarg :msg-id  :reader cp-request-timeout-msg-id)
   (timeout :initarg :timeout :reader cp-request-timeout-timeout))
  (:report (lambda (c s)
             (format s "CP request timed out after ~A s (msg_id=~A)"
                     (cp-request-timeout-timeout c)
                     (cp-request-timeout-msg-id c)))))

;;; --- waiter -------------------------------------------------------------

(defstruct cp-waiter
  "Per-request rendezvous object.  Never shared between callers."
  (msg-id  nil :type (or null string))
  (lock    (bt:make-lock "cp-waiter-lock"))
  (cond-var (bt:make-condition-variable :name "cp-waiter-cv"))
  (result  :pending)              ; :pending | plist | :timeout
  (delivered-p nil))

;;; --- client -------------------------------------------------------------

(defclass cp-client ()
  ((driver :accessor cp-client-driver :initarg :driver)
   ;; G1.b: pending-request table keyed by msg_id -> cp-waiter.
   (pending-requests :accessor cp-client-pending-requests
                     :initform (make-hash-table :test #'equal))
   (pending-lock     :accessor cp-client-pending-lock
                     :initform (bt:make-lock "cp-pending-lock"))
   ;; Legacy single-response slots retained so existing code that accesses
   ;; the accessors keeps working (e.g. direct REPL poking in scripts/).
   ;; The G1.b send path no longer uses these.
   (last-response :accessor cp-client-last-response :initform nil)
   (response-lock :accessor cp-client-response-lock
                  :initform (bt:make-lock "cp-response-lock"))
   (response-cond :accessor cp-client-response-cond
                  :initform (bt:make-condition-variable :name "cp-response-cond"))))

;;; --- msg_id extraction --------------------------------------------------

(defun %extract-reply-msg-id (line)
  "Return two values: (PARENT-MSG-ID HEADER-MSG-ID) from a JSON reply LINE.
   Either may be NIL if the corresponding field is missing or blank.
   Legacy flat replies (no `header' key) return (NIL NIL)."
  (when (and (stringp line) (plusp (length line)) (char= (char line 0) #\{))
    (handler-case
        (let ((obj (shasht:read-json line)))
          (when (hash-table-p obj)
            (let* ((parent     (%hash-get obj "parent_header"))
                   (header     (%hash-get obj "header"))
                   (parent-mid (and (hash-table-p parent)
                                    (%hash-get parent "msg_id")))
                   (header-mid (and (hash-table-p header)
                                    (%hash-get header "msg_id"))))
              ;; Treat "" as absent — the empty parent_header object from
              ;; %make-envelope has no msg_id key at all, but be defensive
              ;; against servers that echo an empty string.
              (values (and parent-mid (plusp (length parent-mid)) parent-mid)
                      (and header-mid (plusp (length header-mid)) header-mid)))))
      (error () (values nil nil)))))

(defun %extract-outgoing-msg-id (json-string)
  "Pull the header.msg_id out of an outgoing frame just-serialised by the
   make-cp-* helpers.  Returns NIL if JSON-STRING is not parseable or lacks
   a header.msg_id."
  (handler-case
      (let ((obj (shasht:read-json json-string)))
        (and (hash-table-p obj)
             (let ((header (%hash-get obj "header")))
               (and (hash-table-p header) (%hash-get header "msg_id")))))
    (error () nil)))

;;; --- pending table operations -------------------------------------------

(defun %register-waiter (client waiter)
  "Register WAITER under its msg-id in CLIENT's pending table.
   Idempotent — re-registering the same waiter overwrites."
  (bt:with-lock-held ((cp-client-pending-lock client))
    (setf (gethash (cp-waiter-msg-id waiter)
                   (cp-client-pending-requests client))
          waiter)))

(defun %unregister-waiter (client msg-id)
  "Remove the waiter keyed by MSG-ID from CLIENT's pending table (if any).
   Return the waiter that was removed, or NIL."
  (bt:with-lock-held ((cp-client-pending-lock client))
    (let ((w (gethash msg-id (cp-client-pending-requests client))))
      (when w
        (remhash msg-id (cp-client-pending-requests client)))
      w)))

(defun %pending-count (client)
  "Return the number of waiters currently registered."
  (bt:with-lock-held ((cp-client-pending-lock client))
    (hash-table-count (cp-client-pending-requests client))))

(defun %single-pending-waiter (client)
  "If exactly one waiter is pending, return it and its msg-id.
   Otherwise return (values NIL NIL).  Used for legacy-flat positional
   fallback."
  (bt:with-lock-held ((cp-client-pending-lock client))
    (let ((h (cp-client-pending-requests client)))
      (if (= 1 (hash-table-count h))
          (let (solo solo-id)
            (maphash (lambda (k v) (setf solo v solo-id k)) h)
            (values solo solo-id))
          (values nil nil)))))

;;; --- delivery + read loop ----------------------------------------------

(defun %complete-waiter (waiter result)
  "Set RESULT on WAITER and wake the waiting thread.  Thread-safe."
  (bt:with-lock-held ((cp-waiter-lock waiter))
    (setf (cp-waiter-result waiter) result
          (cp-waiter-delivered-p waiter) t)
    (bt:condition-notify (cp-waiter-cond-var waiter))))

(defun %log-unmatched-reply (line reason)
  "Broadcast channel for replies with no matching waiter.  For now, just
   log to *error-output* — a future atom may expose a subscription API."
  (format *error-output* "[cp-client] unmatched reply (~A): ~A~%"
          reason
          (if (> (length line) 120)
              (concatenate 'string (subseq line 0 120) "...")
              line)))

(defun %deliver-cp-message (client line)
  "Route an incoming raw LINE to the matching waiter.

   Routing order:
     1. Parse LINE for parent_header.msg_id (preferred) and header.msg_id.
     2. If parent_header.msg_id matches a pending waiter -> deliver.
     3. Else if header.msg_id matches a pending waiter (server echo
        convention used before G1.c) -> deliver.
     4. Else if LINE is legacy flat (no header at all) AND there is
        exactly one pending waiter -> positional fallback: deliver to
        that sole waiter.  This preserves single-caller back-compat
        with pre-G1.b callers that rely on in-order replies.
     5. Otherwise -> drop on the broadcast channel via
        %log-unmatched-reply (read loop continues; no crash).

   Also updates CLIENT's legacy last-response slot for any consumer that
   still reads it directly.  Errors in parsing LINE are logged, not raised."
  (bt:with-lock-held ((cp-client-response-lock client))
    (setf (cp-client-last-response client) line)
    (bt:condition-notify (cp-client-response-cond client)))
  (multiple-value-bind (parent-mid header-mid)
      (%extract-reply-msg-id line)
    (let* ((parsed   (handler-case (cp-parse-response line)
                       (error (c)
                         (%log-unmatched-reply
                          line (format nil "parse-error: ~A" c))
                         nil))))
      (cond
        ;; (2) correlated by parent_header.msg_id
        (parent-mid
         (let ((w (%unregister-waiter client parent-mid)))
           (if w
               (%complete-waiter w parsed)
               (%log-unmatched-reply
                line (format nil "no waiter for parent_header.msg_id=~A"
                             parent-mid)))))
        ;; (3) correlated by header.msg_id (G1.a server-echo fallback)
        (header-mid
         (let ((w (%unregister-waiter client header-mid)))
           (if w
               (%complete-waiter w parsed)
               ;; Not a correlated reply — try positional fallback in case
               ;; this is actually a server-originated frame that happens
               ;; to carry a header.msg_id unrelated to any request.
               (%legacy-flat-fallback client line parsed))))
        ;; (4)/(5) legacy flat — no header, no parent_header
        (t
         (%legacy-flat-fallback client line parsed))))))

(defun %legacy-flat-fallback (client line parsed)
  "When no msg_id correlation is possible, route to the single pending
   waiter (positional fallback) or broadcast."
  (multiple-value-bind (solo solo-id) (%single-pending-waiter client)
    (cond
      (solo
       ;; Snap the solo waiter out of the table and deliver.
       (%unregister-waiter client solo-id)
       (%complete-waiter solo parsed))
      (t
       (%log-unmatched-reply
        line "legacy-flat with 0 or 2+ pending waiters")))))

;;; --- send seam ----------------------------------------------------------

(defvar *cp-send-impl* nil
  "When non-NIL, overrides the socket send in %cp-raw-send.  Tests bind
   this to a lambda (lambda (client json-string) ...) that captures the
   outgoing frame instead of touching a real WebSocket.")

(defun %cp-raw-send (client json-string)
  "Ship JSON-STRING over CLIENT's socket, or route via *cp-send-impl* when
   set (tests).  Never holds the pending-lock."
  (cond
    (*cp-send-impl*
     (funcall *cp-send-impl* client json-string))
    ((eq client :mock-client)
     ;; :mock-client is a sentinel used by offline unit tests that never
     ;; open a real driver.  We drop the frame on the floor — the legacy
     ;; send-cp-command path returns a synthetic response below.
     nil)
    (t
     (wsd:send (cp-client-driver client) json-string))))

;;; --- connect / disconnect -----------------------------------------------

(defun connect-cp (&key (host "localhost") (port 8080))
  "Connect to the CP WebSocket endpoint at ws://<host>:<port>/ws.
   Returns a client object whose :message handler routes replies into
   the pending-request table (see %deliver-cp-message)."
  (let* ((url (format nil "ws://~A:~D/ws" host port))
         (driver (wsd:make-client url))
         (client (make-instance 'cp-client :driver driver)))
    (wsd:on :message driver
            (lambda (message)
              (handler-case
                  (%deliver-cp-message client message)
                (error (c)
                  (format *error-output*
                          "[cp-client] read-loop error (swallowed): ~A~%" c)))))
    (handler-case
        (wsd:start-connection driver)
      (error (c)
        (warn "CP connection failed: ~A" c)))
    client))

(defun disconnect-cp (client)
  "Closes the CP connection."
  (when (and client (not (eq client :mock-client)))
    (wsd:close-connection (cp-client-driver client))))

;;; --- high-level send ----------------------------------------------------

(defparameter *cp-default-timeout* 30
  "Default timeout (seconds) for a single send-cp-command call.")

(defun %send-via-pending (client command-string timeout)
  "Core G1.b send path: register a per-request waiter keyed by the
   outgoing frame's header.msg_id, ship the frame, and block on the
   waiter's condition variable until the reply arrives or TIMEOUT
   elapses.  Never holds pending-lock across I/O or condition-wait.
   Raises CP-REQUEST-TIMEOUT if no reply arrives within TIMEOUT."
  (let* ((msg-id (%extract-outgoing-msg-id command-string))
         (waiter (make-cp-waiter :msg-id msg-id)))
    (unless msg-id
      ;; Caller gave us a frame without a header (legacy flat frame).
      ;; Fall back to the pre-G1.b blocking-on-last-response behaviour
      ;; so code that hand-crafts a JSON string still works.
      (return-from %send-via-pending
        (%send-via-legacy-last-response client command-string)))
    ;; 1. register
    (%register-waiter client waiter)
    ;; 2. ship
    (handler-case
        (%cp-raw-send client command-string)
      (error (c)
        (%unregister-waiter client msg-id)
        (error c)))
    ;; 3. wait (lock -> condition-wait -> lock released during sleep)
    (bt:with-lock-held ((cp-waiter-lock waiter))
      (unless (cp-waiter-delivered-p waiter)
        (bt:condition-wait (cp-waiter-cond-var waiter)
                           (cp-waiter-lock waiter)
                           :timeout timeout)))
    (cond
      ((cp-waiter-delivered-p waiter)
       (cp-waiter-result waiter))
      (t
       ;; Timeout (or spurious wake + still no result): unregister and
       ;; raise.  A race where the delivery thread fires between our
       ;; delivered-p check and the unregister call is harmless —
       ;; %unregister-waiter is tolerant of missing keys.
       (%unregister-waiter client msg-id)
       (error 'cp-request-timeout
              :msg-id  msg-id
              :timeout timeout)))))

(defun %send-via-legacy-last-response (client command-string)
  "Pre-G1.b path used when the outgoing frame has no header.msg_id —
   serialise on the legacy response-lock + response-cond.  Retained so
   ad-hoc hand-crafted JSON strings still work."
  (bt:with-lock-held ((cp-client-response-lock client))
    (setf (cp-client-last-response client) nil)
    (%cp-raw-send client command-string)
    (bt:condition-wait (cp-client-response-cond client)
                       (cp-client-response-lock client))
    (if (cp-client-last-response client)
        (cp-parse-response (cp-client-last-response client))
        (list "ERR" "NO_RESPONSE"))))

(defun send-cp-command (client command-string &key (timeout *cp-default-timeout*))
  "Sends COMMAND-STRING to the CP server and returns the parsed response.
   Blocks until the reply matching COMMAND-STRING's header.msg_id arrives
   or TIMEOUT seconds elapse, whichever comes first.

   On timeout, signals a CP-REQUEST-TIMEOUT condition and removes the
   pending entry so resources don't leak.

   Legacy call shape (no :timeout keyword) preserved — existing callers
   that pass just the client + string keep working."
  (cond
    ((eq client :mock-client)
     (list "OK" "MOCK"))
    (t
     (%send-via-pending client command-string timeout))))

;;; --- helpers on top of send-cp-command ----------------------------------

(defun wait-for-completion (client session-id &key (timeout 50) (interval 1))
  "Poll state until session becomes idle. Returns t on completion, nil on timeout."
  (loop repeat timeout
        for resp = (handler-case
                       (send-cp-command client (make-cp-state session-id))
                     (cp-request-timeout () nil))
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
