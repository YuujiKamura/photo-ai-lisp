(in-package #:photo-ai-lisp/tests)

(in-suite photo-ai-lisp-tests)

;;; Unit tests for src/cp-protocol.lisp

(test cp-protocol-make-input
  (is (string= "INPUT|photo-ai-lisp|aGVsbG8=" (photo-ai-lisp:make-cp-input "hello")))
  (is (string= "INPUT|test|aGVsbG8=" (photo-ai-lisp:make-cp-input "hello" :from "test")))
  (is (string= "INPUT|photo-ai-lisp|aGVsbG8=|sess-1"
               (photo-ai-lisp:make-cp-input "hello" :session-id "sess-1"))))

(test cp-protocol-make-tail
  (is (string= "TAIL|20" (photo-ai-lisp:make-cp-tail)))
  (is (string= "TAIL|50" (photo-ai-lisp:make-cp-tail :n 50)))
  (is (string= "TAIL|20|sess-1" (photo-ai-lisp:make-cp-tail :session-id "sess-1"))))

(test cp-protocol-make-state
  (is (string= "STATE" (photo-ai-lisp:make-cp-state)))
  (is (string= "STATE|sess-1" (photo-ai-lisp:make-cp-state "sess-1"))))

(test cp-protocol-make-list-tabs
  (is (string= "LIST_TABS" (photo-ai-lisp:make-cp-list-tabs))))

(test cp-protocol-parse-response
  (is (equal '("OK" "ghostty-web" "CAPTURE_PANE")
             (photo-ai-lisp:cp-parse-response "OK|ghostty-web|CAPTURE_PANE")))
  (is (equal '("PONG" "ghostty-web" "1234")
             (photo-ai-lisp:cp-parse-response "PONG|ghostty-web|1234"))))
