(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; Unit tests for src/cp-protocol.lisp (JSON format for Deckpilot)

(test cp-protocol-make-input
  (is (search "\"cmd\":\"INPUT\"" (photo-ai-lisp:make-cp-input "hello")))
  (is (search "\"msg\":\"aGVsbG8=\"" (photo-ai-lisp:make-cp-input "hello")))
  (is (search "\"from\":\"test\"" (photo-ai-lisp:make-cp-input "hello" :from "test")))
  (is (search "\"session\":\"sess-1\"" (photo-ai-lisp:make-cp-input "hello" :session-id "sess-1"))))

(test cp-protocol-make-tail
  (is (search "\"cmd\":\"SHOW\"" (photo-ai-lisp:make-cp-tail)))
  (is (search "\"lines\":50" (photo-ai-lisp:make-cp-tail :n 50)))
  (is (search "\"session\":\"sess-1\"" (photo-ai-lisp:make-cp-tail :session-id "sess-1"))))

(test cp-protocol-make-state
  (is (search "\"cmd\":\"STATE\"" (photo-ai-lisp:make-cp-state)))
  (is (search "\"session\":\"sess-1\"" (photo-ai-lisp:make-cp-state "sess-1"))))

(test cp-protocol-make-list-tabs
  (is (search "\"cmd\":\"LIST\"" (photo-ai-lisp:make-cp-list-tabs))))

(test cp-protocol-parse-response
  (is (equal '("JSON" "{\"res\":\"OK\"}")
             (photo-ai-lisp:cp-parse-response "{\"res\":\"OK\"}")))
  (is (equal '("OK" "legacy")
             (photo-ai-lisp:cp-parse-response "OK|legacy"))))
