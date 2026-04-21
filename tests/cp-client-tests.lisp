(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; ACCEPTANCE SPEC for src/cp-client.lisp
;;; These tests land RED because the implementation in cp-client.lisp signals UNIMPLEMENTED.

(test cp-client-connect-returns-object
  "Connecting to CP should return a non-nil client object."
  ;; Since we don't want to rely on a real server during unit tests,
  ;; we test the stub behavior which should eventually return a client instance.
  (handler-case
      (let ((client (photo-ai-lisp:connect-cp :port 9999)))
        (is-true client)
        (photo-ai-lisp:disconnect-cp client))
    (photo-ai-lisp::unimplemented ()
      (fail "connect-cp is unimplemented"))))

(test cp-client-send-command-sync
  "send-cp-command should send a string and return a parsed response list."
  (handler-case
      (let ((client :mock-client))
        ;; In a real implementation, this would involve mocking the WebSocket stream.
        ;; For now, the spec says it returns a list.
        (is (listp (photo-ai-lisp:send-cp-command client "PING"))))
    (photo-ai-lisp::unimplemented ()
      (fail "send-cp-command is unimplemented"))))

(test cp-client-tail-helper
  "cp-tail should wrap the TAIL command and return the result."
  (handler-case
      (let ((client :mock-client))
        (is (listp (photo-ai-lisp:cp-tail client :n 10))))
    (photo-ai-lisp::unimplemented ()
      (fail "cp-tail is unimplemented"))))

(test cp-client-input-helper
  "cp-input should wrap the INPUT command and return the result."
  (handler-case
      (let ((client :mock-client))
        (is (listp (photo-ai-lisp:cp-input client "hello"))))
    (photo-ai-lisp::unimplemented ()
      (fail "cp-input is unimplemented"))))

;;; --- G1.b: pending-request table ----------------------------------------
;;;
;;; These tests drive the client without opening a real WebSocket.  The
;;; send seam is *cp-send-impl* — a special var that, when set, replaces
;;; the socket send with a capture lambda.  Incoming replies are injected
;;; directly via %deliver-cp-message, which is the same hook the real
;;; :message handler uses.
;;;
;;; We mutate the global *cp-send-impl* directly (inside unwind-protect
;;; for cleanup) rather than LET-binding it, because bordeaux-threads
;;; makes no portable guarantee that worker threads inherit local
;;; dynamic bindings.  The fiveam suite runs tests sequentially in one
;;; thread so global mutation is safe.

(defun %make-stub-client ()
  "Build a cp-client without opening a WebSocket.
   The :driver slot holds a sentinel because nothing in the G1.b send
   path reads it once *cp-send-impl* is in effect."
  (make-instance 'photo-ai-lisp::cp-client :driver :stub))

(defun %reply-envelope (parent-msg-id &key (msg-type "INPUT") (session "sess")
                                           (ok t) (message "sent"))
  "Build a 5-part JSON reply whose parent_header.msg_id is PARENT-MSG-ID.
   Mirrors the shape the CP server is expected to return post-G1.c."
  (let ((escape-msg (with-output-to-string (s)
                      (loop for c across message do
                        (case c
                          (#\\ (write-string "\\\\" s))
                          (#\" (write-string "\\\"" s))
                          (t   (write-char c s)))))))
    (format nil
            "{\"header\":{\"msg_id\":\"~A\",\"msg_type\":\"~A\",\"session\":\"~A\",\"username\":\"cp-server\",\"date\":\"2026-04-21T00:00:00Z\",\"version\":\"5.4\"},\"parent_header\":{\"msg_id\":\"~A\"},\"metadata\":{},\"content\":{\"cmd\":\"~A\",\"ok\":~A,\"message\":\"~A\",\"session\":\"~A\"},\"buffers\":[]}"
            (format nil "reply-of-~A" parent-msg-id)
            msg-type session
            parent-msg-id
            msg-type
            (if ok "true" "false")
            escape-msg
            session)))

(defmacro %with-send-impl ((impl-var) &body body)
  "Bind photo-ai-lisp::*cp-send-impl* to IMPL-VAR (a lambda) for BODY via
   global setf + unwind-protect.  This avoids the LET-vs-MAKE-THREAD
   inheritance non-guarantee in bordeaux-threads."
  (let ((saved (gensym "SAVED-IMPL")))
    `(let ((,saved photo-ai-lisp::*cp-send-impl*))
       (unwind-protect
            (progn
              (setf photo-ai-lisp::*cp-send-impl* ,impl-var)
              ,@body)
         (setf photo-ai-lisp::*cp-send-impl* ,saved)))))

(defun %wait-pending-count (client n &key (tries 200) (interval 0.01))
  "Spin until (= N (%pending-count client)) or TRIES exhaustion.
   Return T on success, NIL on timeout."
  (loop repeat tries
        when (= n (photo-ai-lisp::%pending-count client)) return t
        do (sleep interval)
        finally (return nil)))

(test pending-request-roundtrip-single
  "1 caller, mocked server replies with matching parent_header.msg_id,
   caller gets the reply via G1.b pending-request routing."
  (let* ((client (%make-stub-client))
         (captured-frame nil)
         (send-impl (lambda (c f)
                      (declare (ignore c))
                      (setf captured-frame f))))
    (%with-send-impl (send-impl)
      (let* ((frame (photo-ai-lisp:make-cp-input "hello" :session-id "s-rt"))
             (expected-msg-id (photo-ai-lisp::%extract-outgoing-msg-id frame))
             (delivery
               (bt:make-thread
                (lambda ()
                  ;; Wait until the sender's waiter is registered, then
                  ;; deliver.  The sender ships via *cp-send-impl* AFTER
                  ;; registering, so we watch the pending count.
                  (%wait-pending-count client 1)
                  (photo-ai-lisp::%deliver-cp-message
                   client
                   (%reply-envelope expected-msg-id :session "s-rt")))
                :name "roundtrip-delivery")))
        (let ((resp (photo-ai-lisp:send-cp-command client frame :timeout 2)))
          (bt:join-thread delivery)
          (is (stringp captured-frame)
              "the outgoing frame should have been shipped via *cp-send-impl*")
          (is (listp resp))
          (is (string= "INPUT" (getf resp :cmd)))
          (is (getf resp :ok))
          (is (string= "sent" (getf resp :message))))))))

(test pending-request-parallel-no-crosstalk
  "Two callers issue different requests in separate threads; server
   replies in reversed order.  Each caller must receive its own reply,
   not the other's — this is the whole point of G1.b."
  (let* ((client (%make-stub-client))
         (frame-a (photo-ai-lisp:make-cp-input "aaa" :session-id "sA"))
         (frame-b (photo-ai-lisp:make-cp-input "bbb" :session-id "sB"))
         (id-a (photo-ai-lisp::%extract-outgoing-msg-id frame-a))
         (id-b (photo-ai-lisp::%extract-outgoing-msg-id frame-b))
         (outbox-lock (bt:make-lock))
         (outbox nil)
         (result-a :pending)
         (result-b :pending))
    (is (not (string= id-a id-b))
        "msg_ids for two separate frames must differ")
    (%with-send-impl ((lambda (c f)
                        (declare (ignore c))
                        (bt:with-lock-held (outbox-lock) (push f outbox))))
      (let* ((t-a (bt:make-thread
                   (lambda ()
                     (handler-case
                         (setf result-a
                               (photo-ai-lisp:send-cp-command
                                client frame-a :timeout 3))
                       (error (c) (setf result-a (list :err c)))))
                   :name "caller-a"))
             (t-b (bt:make-thread
                   (lambda ()
                     (handler-case
                         (setf result-b
                               (photo-ai-lisp:send-cp-command
                                client frame-b :timeout 3))
                       (error (c) (setf result-b (list :err c)))))
                   :name "caller-b")))
        ;; wait for both send-cp-commands to have registered their
        ;; waiters (both ship through our outbox lambda BEFORE blocking
        ;; on condition-wait, so 2 waiters in the table <=> both shipped)
        (is (%wait-pending-count client 2)
            "both threads must have registered their waiters")
        (is (= 2 (length outbox))
            "both threads must have shipped their frames via *cp-send-impl*")
        ;; deliver replies in REVERSED order to force correlation
        (photo-ai-lisp::%deliver-cp-message
         client (%reply-envelope id-b :session "sB" :message "reply-for-bbb"))
        (photo-ai-lisp::%deliver-cp-message
         client (%reply-envelope id-a :session "sA" :message "reply-for-aaa"))
        (bt:join-thread t-a)
        (bt:join-thread t-b)
        ;; Each caller must see ITS OWN reply, not the other's.
        (is (listp result-a))
        (is (listp result-b))
        (is (string= "reply-for-aaa" (getf result-a :message))
            (format nil "caller A got ~S (expected reply-for-aaa)" result-a))
        (is (string= "reply-for-bbb" (getf result-b :message))
            (format nil "caller B got ~S (expected reply-for-bbb)" result-b))
        (is (string= "sA" (getf result-a :session)))
        (is (string= "sB" (getf result-b :session)))
        ;; Pending table must be empty after delivery.
        (is (zerop (photo-ai-lisp::%pending-count client)))))))

(test pending-request-timeout-raises
  "When no reply arrives within TIMEOUT, send-cp-command must signal a
   CP-REQUEST-TIMEOUT and leave no entry in the pending table."
  (let* ((client (%make-stub-client))
         (frame  (photo-ai-lisp:make-cp-state "s-to")))
    (%with-send-impl ((lambda (c f) (declare (ignore c f)) nil))
      (signals photo-ai-lisp:cp-request-timeout
        (photo-ai-lisp:send-cp-command client frame :timeout 0.2))
      (is (zerop (photo-ai-lisp::%pending-count client))
          "timed-out waiter must be removed from the pending table"))))

(test pending-request-unmatched-reply-does-not-crash
  "A reply with a msg_id not in the pending table must not wake any
   waiter and must not crash the read loop.  The reply is dropped on
   the broadcast channel (logged, not raised)."
  (let* ((client (%make-stub-client))
         (frame  (photo-ai-lisp:make-cp-input "x" :session-id "s-um"))
         (real-id (photo-ai-lisp::%extract-outgoing-msg-id frame))
         (sender-result :pending))
    (%with-send-impl ((lambda (c f) (declare (ignore c f)) nil))
      (let ((t-sender
              (bt:make-thread
               (lambda ()
                 (handler-case
                     (setf sender-result
                           (photo-ai-lisp:send-cp-command
                            client frame :timeout 2))
                   (error (c) (setf sender-result (list :err c)))))
               :name "real-sender")))
        ;; wait until the sender has its waiter in the table
        (is (%wait-pending-count client 1))
        ;; Inject a reply for a DIFFERENT msg_id.  It must be logged and
        ;; dropped, not wake the real waiter.
        (let ((log (with-output-to-string (*error-output*)
                     (photo-ai-lisp::%deliver-cp-message
                      client
                      (%reply-envelope "nonexistent-msg-id"
                                       :session "s-other"
                                       :message "stray")))))
          (is (search "unmatched" log)
              (format nil "broadcast log should mention 'unmatched': ~S" log))
          (is (search "no waiter" log)))
        ;; Real waiter must still be pending.
        (is (= 1 (photo-ai-lisp::%pending-count client)))
        (is (eq sender-result :pending))
        ;; Now deliver the correct reply so the test cleans up.
        (photo-ai-lisp::%deliver-cp-message
         client (%reply-envelope real-id :session "s-um" :message "ok"))
        (bt:join-thread t-sender)
        (is (listp sender-result))
        (is (string= "ok" (getf sender-result :message)))
        (is (zerop (photo-ai-lisp::%pending-count client)))))))

(test pending-request-legacy-flat-reply-still-routes
  "Policy: a legacy flat reply (no header, no parent_header) routes to
   the sole pending waiter via positional fallback.  When 0 or 2+
   waiters are pending, it goes to the broadcast channel instead.
   This preserves pre-G1.b single-caller back-compat while refusing to
   paper over crosstalk in the parallel case."
  (%with-send-impl ((lambda (c f) (declare (ignore c f)) nil))
    ;; --- case 1: exactly 1 waiter pending → positional delivery ---
    (let* ((client (%make-stub-client))
           (frame (photo-ai-lisp:make-cp-input "solo" :session-id "s-lf"))
           (result :pending)
           (t-a (bt:make-thread
                 (lambda ()
                   (handler-case
                       (setf result
                             (photo-ai-lisp:send-cp-command
                              client frame :timeout 2))
                     (error (c) (setf result (list :err c)))))
                 :name "solo-sender")))
      (is (%wait-pending-count client 1))
      ;; legacy flat reply — no header, no parent_header
      (photo-ai-lisp::%deliver-cp-message
       client
       "{\"cmd\":\"INPUT\",\"ok\":true,\"message\":\"legacy-flat-routed\",\"session\":\"s-lf\"}")
      (bt:join-thread t-a)
      (is (listp result))
      (is (string= "legacy-flat-routed" (getf result :message))
          (format nil "positional fallback should deliver legacy flat to the sole waiter; got ~S" result))
      (is (zerop (photo-ai-lisp::%pending-count client))))
    ;; --- case 2: 0 waiters pending → logged/broadcast only, no crash ---
    (let* ((client (%make-stub-client))
           (log (with-output-to-string (*error-output*)
                  (photo-ai-lisp::%deliver-cp-message
                   client
                   "{\"cmd\":\"STATE\",\"ok\":true,\"status\":\"idle\"}"))))
      (is (search "unmatched" log))
      (is (zerop (photo-ai-lisp::%pending-count client))))))
