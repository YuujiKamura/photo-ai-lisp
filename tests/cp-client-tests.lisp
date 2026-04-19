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
