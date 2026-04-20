(in-package #:photo-ai-lisp/tests)

;;; End-to-end scenario: prove that a command sent via the HTTP
;;; /api/inject endpoint actually appears in the output stream of a
;;; WebSocket client attached to /ws/shell. This is the Rust-version
;;; equivalent of 'CP INPUT → terminal reflects' — automated.
;;;
;;; Sequence:
;;;   1. Start the hunchentoot+ws acceptor on a random high port.
;;;   2. Open a websocket-driver client to ws://.../ws/shell. This
;;;      simulates the browser iframe's xterm.js WS.
;;;   3. HTTP GET /api/inject?text=echo%20SENTINEL-N%0D%0A.
;;;   4. Wait up to 5s, collecting every text frame the client gets.
;;;   5. Assert that at least one frame contains SENTINEL-N.

;; websocket-driver and drakma are pulled in via the asd depends-on.

(5am:def-suite inject-e2e-suite :description "browser round-trip e2e")
(5am:in-suite inject-e2e-suite)

(defun %pick-test-port ()
  "Pick a port unlikely to clash with the developer's live instance
   on 8090 and unlikely to repeat across test runs."
  (+ 9000 (random 900)))

(defun %http-get (url &key parameters (timeout 3))
  (handler-case
      (let ((drakma:*drakma-default-external-format* :utf-8))
        (multiple-value-bind (body status)
            (drakma:http-request url
                                 :method :get
                                 :parameters parameters
                                 :connection-timeout timeout)
          (values (if (stringp body) body
                      (when body (map 'string #'code-char body)))
                  status)))
    (error (e) (values (princ-to-string e) nil))))

(5am:test inject-reaches-connected-ws-client
  "Full round trip: start server → connect WS client → HTTP inject →
   assert sentinel appears in client's received frames within 5s."
  (let* ((port     (%pick-test-port))
         (sentinel (format nil "SENTINEL-~a" (random 1000000)))
         (received (make-array 4096 :element-type 'character
                                    :adjustable t :fill-pointer 0))
         (received-lock (bordeaux-threads:make-lock "received"))
         (client nil)
         (connected nil))
    (unwind-protect
        (progn
          ;; 1. Start the server.
          (photo-ai-lisp:start :port port)
          (sleep 0.3)
          ;; 2. Connect WS client (simulated browser iframe).
          (setf client (wsd:make-client
                        (format nil "ws://127.0.0.1:~a/ws/shell" port)))
          (wsd:on :open client
                  (lambda () (setf connected t)))
          (wsd:on :message client
                  (lambda (msg)
                    (bordeaux-threads:with-lock-held (received-lock)
                      (loop for c across msg
                            do (vector-push-extend c received)))))
          (wsd:start-connection client)
          (let ((deadline (+ (get-internal-real-time)
                             (floor (* 2 internal-time-units-per-second)))))
            (loop until (or connected (> (get-internal-real-time) deadline))
                  do (sleep 0.05)))
          (5am:is-true connected "WS client failed to open")
          ;; Give cmd.exe banner time to flow.
          (sleep 0.5)
          ;; 3. HTTP inject — drakma URL-encodes the :parameters value once.
          (let ((url (format nil "http://127.0.0.1:~a/api/inject" port))
                ;; Bare LF — %normalize-child-input is idempotent over
                ;; trailing Enter runs (see term.lisp), but using LF here
                ;; keeps the fixture shape identical to the live picker-
                ;; inject / xterm keystroke wire, so this e2e exercises
                ;; the real byte path rather than relying on the
                ;; normalizer's defensive collapse.
                (text (format nil "echo ~a~c" sentinel #\Newline)))
            (multiple-value-bind (body status)
                (%http-get url :parameters `(("text" . ,text)))
              (5am:is (eql 200 status)
                      "inject HTTP status ~a body=~a" status body)
              (5am:is (search "\"ok\":true" body)
                      "inject body missing ok:true — ~a" body)))
          ;; 4. Wait up to 5s for the sentinel to round-trip.
          (let ((deadline (+ (get-internal-real-time)
                             (floor (* 5 internal-time-units-per-second)))))
            (loop until
                  (or (bordeaux-threads:with-lock-held (received-lock)
                        (search sentinel received))
                      (> (get-internal-real-time) deadline))
                  do (sleep 0.1)))
          ;; 5. Assert.
          (let ((got (bordeaux-threads:with-lock-held (received-lock)
                       (coerce received 'simple-string))))
            (5am:is (search sentinel got)
                    "sentinel ~a not observed in ~a bytes of WS output"
                    sentinel (length got))))
      ;; Cleanup.
      (ignore-errors (when client (wsd:close-connection client)))
      (sleep 0.2)
      (ignore-errors (photo-ai-lisp:stop)))))
