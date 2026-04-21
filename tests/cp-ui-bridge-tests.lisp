(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; Acceptance specs for src/cp-ui-bridge.lisp (issue #19 T2.b).
;;; Tests are pure Lisp — no HTTP server started.  The bridge handler
;;; function is called directly and the returned JSON body is inspected.

;;; T2.h helper: temporarily unset PHOTO_AI_LISP_DEMO_AGENT for legacy
;;; branch tests, in case CI (or a developer) has it set in the env.
;;; Using (setf (uiop:getenv ...) nil) relies on uiop's setenv shim,
;;; which maps to sb-posix:setenv on SBCL/POSIX and SetEnvironmentVariableA
;;; on SBCL/Windows. Both accept "" as the unset-equivalent.
(defmacro %with-demo-agent-unset (&body body)
  `(let ((saved (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT")))
     (unwind-protect
          (progn
            (setf (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT") "")
            ,@body)
       (when saved
         (setf (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT") saved)))))

;; ---- T2.b-1 : 503 body when *demo-session-id* is nil ------------------

(5am:test cp-ui-bridge-nil-session-returns-error-body
  "With *demo-session-id* nil, input-bridge-handler must return the
   error JSON body (the HTTP 503 status is set by the dispatcher wrapper;
   here we verify only the string contract).

   T2.h pivot: also asserts the PHOTO_AI_LISP_DEMO_AGENT env var is
   NOT set, so the legacy CP branch is exercised (not the shell-broadcast
   branch)."
  (%with-demo-agent-unset
    (let ((photo-ai-lisp:*demo-session-id* nil))
      (let ((body (photo-ai-lisp:input-bridge-handler "fake" "echo hello")))
        (5am:is (search "error" body)
                "body should contain 'error' key")
        (5am:is (search "no demo session" body)
                "body should contain the 'no demo session' message")))))

;; ---- T2.b-2 : 200 body when *demo-session-id* is set ------------------

(5am:test cp-ui-bridge-with-session-returns-ok-body
  "With *demo-session-id* bound to a non-nil string and *demo-cp-client*
   left as nil (falls back to :mock-client inside %cp-client-or-mock),
   input-bridge-handler must return a JSON body containing 'ok':true and
   the session id.

   T2.h pivot: PHOTO_AI_LISP_DEMO_AGENT must be unset for this test to
   exercise the legacy CP branch (otherwise the demo-mode branch takes
   over and returns a different JSON shape)."
  (%with-demo-agent-unset
    (let ((photo-ai-lisp:*demo-session-id* "test-sess-001")
          (photo-ai-lisp:*demo-cp-client*  nil))
      (let ((body (photo-ai-lisp:input-bridge-handler "test-case" "echo hello from hub")))
        (5am:is (search "\"ok\":true" body)
                "body should contain ok:true")
        (5am:is (search "test-sess-001" body)
                "body should echo the session id")
        (5am:is (search "bytes" body)
                "body should contain byte count field")))))

;; ---- T2.h : demo-mode branch returns error body when no /ws/shell is open -----

(5am:test input-bridge-demo-mode-no-recipients-returns-error
  "With PHOTO_AI_LISP_DEMO_AGENT set but no /ws/shell client connected,
   shell-broadcast-input reaches zero recipients, so input-bridge-handler
   must return the 'no /ws/shell client connected' error body. The
   dispatcher wrapper in src/main.lisp will set HTTP 503 based on the
   'error' substring in the body."
  (let ((saved (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT")))
    (unwind-protect
         (progn
           ;; No /ws/shell client is ever connected during unit tests
           ;; (acceptor isn't running), so shell-broadcast-input counts 0
           ;; recipients by construction. Setting the env var forces the
           ;; demo-mode branch without needing to mock anything.
           (setf (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT")
                 "claude --model sonnet")
           (let ((photo-ai-lisp:*demo-session-id* nil)
                 (photo-ai-lisp:*demo-cp-client*  nil))
             (let ((body (photo-ai-lisp:input-bridge-handler "demo" "echo hi")))
               (5am:is (search "\"error\"" body)
                       "body must contain JSON 'error' key so dispatcher 503s")
               (5am:is (search "no /ws/shell" body)
                       "body must name the missing /ws/shell client"))))
      (if saved
          (setf (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT") saved)
          (setf (uiop:getenv "PHOTO_AI_LISP_DEMO_AGENT") "")))))

;; ---- T2.c — parse-demo-session-name unit tests ----------------------------

(5am:test boot-hub-parse-demo-session-simple
  "Single line 'ghostty-12345\\n' -> 'ghostty-12345'."
  (5am:is (equal "ghostty-12345"
                 (photo-ai-lisp:parse-demo-session-name
                  (format nil "ghostty-12345~%")))
          "simple ghostty session name must be returned verbatim"))

(5am:test boot-hub-parse-demo-session-multiline
  "Noise lines before the session name: last non-empty line wins."
  (5am:is (equal "ghostty-67890"
                 (photo-ai-lisp:parse-demo-session-name
                  (format nil "some noise~%ghostty-67890~%")))
          "last non-empty line should be returned even when prefix noise is present"))

(5am:test boot-hub-parse-demo-session-bad-input
  "Empty string and non-ghostty- prefix → nil."
  (5am:is (null (photo-ai-lisp:parse-demo-session-name ""))
          "empty string must return nil")
  (5am:is (null (photo-ai-lisp:parse-demo-session-name
                 (format nil "notasession~%")))
          "line not starting with ghostty- must return nil"))

;; ---- G2.a (issue #30 Phase 2 Team β) --------------------------------------
;;
;; These tests exercise broadcast-status + the input-dispatch-path emission
;; without touching a real WebSocket.  The broadcast primitive routes to
;; control.lisp's control-broadcast via FUNCALL, so we swap control-broadcast's
;; function cell out for a capturing lambda inside %WITH-STATUS-RECEIVER.
;; That's cleaner than mocking /ws/control clients and closer to what a real
;; UI client sees on the wire.
;;
;; The %with-send-impl idiom below is borrowed from cp-client-tests.lisp: we
;; replace the CP-client socket send with a lambda so send-cp-command never
;; opens a real WebSocket.  For the legacy CP branch to exercise the real
;; send-cp-command path (and thus the error propagation in handler-case), we
;; bind *demo-cp-client* to a stub cp-client instead of the :mock-client
;; sentinel — :mock-client short-circuits in send-cp-command before any
;; envelope is built.

(defun %capture-statuses-thunk ()
  "Return (values capture-list capture-fn).  capture-fn can be used as a
   drop-in replacement for control-broadcast: each call appends the TEXT
   argument to the capture-list (in FIFO order) and returns 1 to mimic a
   single live subscriber."
  (let ((captured nil)
        (lock (bordeaux-threads:make-lock)))
    (values
     (lambda () (bordeaux-threads:with-lock-held (lock) (reverse captured)))
     (lambda (text)
       (bordeaux-threads:with-lock-held (lock)
         (push text captured))
       1))))

(defmacro %with-status-receiver ((get-fn-var) &body body)
  "Install a capturing stand-in for control-broadcast while BODY runs.
   GET-FN-VAR is bound to a zero-arg function that returns the list of
   captured status JSON strings (FIFO).  Restores the original function
   cell (or makes control-broadcast unbound if it was originally unbound)
   on exit."
  (let ((saved-fn    (gensym "SAVED-FN"))
        (was-bound   (gensym "WAS-BOUND"))
        (capture-fn  (gensym "CAPTURE-FN")))
    `(multiple-value-bind (,get-fn-var ,capture-fn) (%capture-statuses-thunk)
       (let ((,was-bound (fboundp 'photo-ai-lisp::control-broadcast))
             (,saved-fn  (and (fboundp 'photo-ai-lisp::control-broadcast)
                              (symbol-function 'photo-ai-lisp::control-broadcast))))
         (unwind-protect
              (progn
                (setf (symbol-function 'photo-ai-lisp::control-broadcast) ,capture-fn)
                ,@body)
           (if ,was-bound
               (setf (symbol-function 'photo-ai-lisp::control-broadcast) ,saved-fn)
               (fmakunbound 'photo-ai-lisp::control-broadcast)))))))

(defun %parse-status-json (json-string)
  "Shortcut: parse a status envelope string into a hash-table."
  (shasht:read-json json-string))

(defun %status-content (parsed-hash key)
  (gethash key (gethash "content" parsed-hash)))

(defun %status-header (parsed-hash key)
  (gethash key (gethash "header" parsed-hash)))

(5am:test broadcast-status-emits-envelope-with-status-msg-type
  "build-status-envelope / broadcast-status must emit a 5-part envelope
   whose header.msg_type is \"status\" and whose content carries state /
   mode / target_msg_id."
  (let* ((raw (photo-ai-lisp:build-status-envelope
               :msg-id "req-xyz"
               :state :processing
               :mode :1
               :session-id "sess-β"))
         (parsed (%parse-status-json raw)))
    (5am:is (hash-table-p (gethash "header" parsed)))
    (5am:is (string= "status" (%status-header parsed "msg_type"))
            "header.msg_type must be \"status\"")
    (5am:is (= 36 (length (%status-header parsed "msg_id")))
            "status envelope's own header.msg_id must be a fresh UUID, not the target_msg_id")
    (5am:is (string= "sess-β" (%status-header parsed "session"))
            "session must round-trip via the header")
    (let ((content (gethash "content" parsed)))
      (5am:is (hash-table-p content))
      (5am:is (string= "processing" (gethash "state" content)))
      (5am:is (string= "1"          (gethash "mode"  content)))
      (5am:is (string= "req-xyz"    (gethash "target_msg_id" content))
              "target_msg_id must carry the ORIGINATING request's msg_id, not the status envelope's own one"))))

(5am:test broadcast-with-no-ui-clients-is-noop
  "With zero /ws/control subscribers (control-broadcast sees an empty
   client list — or control-broadcast is not even fbound because
   control.lisp wasn't loaded), broadcast-status must not raise and
   must return an integer recipient count."
  ;; In the live image, control-broadcast IS fbound (control.lisp loads
  ;; unconditionally as part of :photo-ai-lisp), but the *control-clients*
  ;; list is empty during unit tests because the acceptor never starts.
  ;; control-broadcast returns the count (0) without raising.
  (5am:finishes
    (photo-ai-lisp:broadcast-status :msg-id "whatever"
                                    :state :idle
                                    :mode :1))
  ;; Also cover the defensive branch where control-broadcast is missing.
  (let ((was-bound (fboundp 'photo-ai-lisp::control-broadcast))
        (saved-fn  (and (fboundp 'photo-ai-lisp::control-broadcast)
                        (symbol-function 'photo-ai-lisp::control-broadcast))))
    (unwind-protect
         (progn
           (fmakunbound 'photo-ai-lisp::control-broadcast)
           (5am:finishes
             (photo-ai-lisp:broadcast-status :msg-id "x"
                                             :state :processing
                                             :mode :1))
           (5am:is (zerop
                    (photo-ai-lisp:broadcast-status :msg-id "x"
                                                    :state :processing
                                                    :mode :1))
                   "with control-broadcast unbound, broadcast-status must return 0"))
      (when was-bound
        (setf (symbol-function 'photo-ai-lisp::control-broadcast) saved-fn)))))

(defun %make-stub-cp-client ()
  "Build a cp-client without opening a WebSocket — shared idiom with
   cp-client-tests.lisp %make-stub-client."
  (make-instance 'photo-ai-lisp::cp-client :driver :stub))

(defmacro %with-bridge-send-impl ((impl-var) &body body)
  "Install IMPL-VAR as photo-ai-lisp::*cp-send-impl* for BODY so
   send-cp-command routes through the stub instead of a real socket."
  (let ((saved (gensym "SAVED-IMPL")))
    `(let ((,saved photo-ai-lisp::*cp-send-impl*))
       (unwind-protect
            (progn
              (setf photo-ai-lisp::*cp-send-impl* ,impl-var)
              ,@body)
         (setf photo-ai-lisp::*cp-send-impl* ,saved)))))

(5am:test input-dispatch-emits-processing-then-idle
  "When input-bridge-handler takes the legacy CP branch and the send
   succeeds, it must broadcast a :processing status BEFORE shipping the
   frame and an :idle status AFTER the reply.  Both statuses carry the
   same target_msg_id — the request frame's header.msg_id — so a UI can
   correlate them."
  (%with-demo-agent-unset
    (let ((photo-ai-lisp:*demo-session-id* "sess-g2a-ok")
          (photo-ai-lisp:*demo-cp-client*  (%make-stub-cp-client)))
      (%with-status-receiver (get-statuses)
        ;; Install a send-impl that instantly delivers a matching reply
        ;; so send-cp-command returns instead of blocking on timeout.
        (let ((send-impl
                (lambda (client frame)
                  (let* ((mid (photo-ai-lisp::%extract-outgoing-msg-id frame))
                         (reply (format nil
                                        "{\"header\":{\"msg_id\":\"r-~A\",\"msg_type\":\"INPUT\",\"session\":\"sess-g2a-ok\",\"username\":\"cp\",\"date\":\"2026-04-21T00:00:00Z\",\"version\":\"5.4\"},\"parent_header\":{\"msg_id\":\"~A\"},\"metadata\":{},\"content\":{\"cmd\":\"INPUT\",\"ok\":true,\"message\":\"ack\"},\"buffers\":[]}"
                                        mid mid)))
                    ;; Deliver the reply on a worker thread so the sender
                    ;; reaches its condition-wait first (mirrors the real
                    ;; driver's :message callback from another thread).
                    (bt:make-thread
                     (lambda ()
                       (sleep 0.02)
                       (photo-ai-lisp::%deliver-cp-message client reply))
                     :name "g2a-ok-delivery")))))
          (%with-bridge-send-impl (send-impl)
            (let ((body (photo-ai-lisp:input-bridge-handler "case-ok" "hello")))
              (5am:is (search "\"ok\":true" body)
                      "dispatch must succeed when the stubbed reply is delivered")))
          (let ((statuses (mapcar #'%parse-status-json (funcall get-statuses))))
            (5am:is (= 2 (length statuses))
                    (format nil "exactly 2 status events (processing + idle); got ~D"
                            (length statuses)))
            (when (= 2 (length statuses))
              (let ((s0 (first statuses))
                    (s1 (second statuses)))
                (5am:is (string= "status" (%status-header s0 "msg_type")))
                (5am:is (string= "status" (%status-header s1 "msg_type")))
                (5am:is (string= "processing" (%status-content s0 "state"))
                        "first status must be processing")
                (5am:is (string= "idle" (%status-content s1 "state"))
                        "second status must be idle")
                (5am:is (string= (%status-content s0 "target_msg_id")
                                 (%status-content s1 "target_msg_id"))
                        "both statuses must share the same target_msg_id")
                (5am:is (plusp (length (%status-content s0 "target_msg_id")))
                        "target_msg_id must not be empty when the bridge built an envelope")))))))))

(5am:test input-dispatch-on-error-emits-error-status
  "When send-cp-command raises (e.g. cp-request-timeout), input-bridge-handler
   must emit a :processing status, then an :error status carrying the
   condition class name, BEFORE propagating the error."
  (%with-demo-agent-unset
    (let ((photo-ai-lisp:*demo-session-id* "sess-g2a-err")
          (photo-ai-lisp:*demo-cp-client*  (%make-stub-cp-client)))
      (%with-status-receiver (get-statuses)
        ;; Send-impl drops the frame; with no delivery, send-cp-command
        ;; will hit its timeout and raise cp-request-timeout.
        (%with-bridge-send-impl ((lambda (c f) (declare (ignore c f)) nil))
          (let ((photo-ai-lisp::*cp-default-timeout* 0.1))
            (5am:signals photo-ai-lisp:cp-request-timeout
              (photo-ai-lisp:input-bridge-handler "case-err" "boom"))))
        (let ((statuses (mapcar #'%parse-status-json (funcall get-statuses))))
          (5am:is (= 2 (length statuses))
                  (format nil "exactly 2 status events (processing + error); got ~D"
                          (length statuses)))
          (when (= 2 (length statuses))
            (let ((s0 (first statuses))
                  (s1 (second statuses)))
              (5am:is (string= "processing" (%status-content s0 "state")))
              (5am:is (string= "error"      (%status-content s1 "state"))
                      "terminal status on a failed dispatch must be :error")
              (5am:is (string= (%status-content s0 "target_msg_id")
                               (%status-content s1 "target_msg_id"))
                      "error status must reference the same target_msg_id")
              (let ((ec (%status-content s1 "error_class")))
                (5am:is (stringp ec)
                        "error envelope must carry content.error_class")
                (5am:is (search "cp-request-timeout" ec)
                        (format nil "error_class must name the condition; got ~S" ec))))))))))
