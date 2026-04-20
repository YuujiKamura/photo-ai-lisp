(in-package #:photo-ai-lisp/tests)

(5am:def-suite inject-suite :description "shared-session text injection")
(5am:in-suite inject-suite)

(5am:test shell-broadcast-no-clients-returns-zero
  "With no /ws/shell clients connected, broadcast reaches nobody."
  (let ((photo-ai-lisp::*shell-clients* '()))
    (photo-ai-lisp::shell-trace-clear)
    (5am:is (zerop (photo-ai-lisp::shell-broadcast-input "anything")))))

(5am:test shell-broadcast-records-in-trace
  "Broadcast records the text in the shell-trace ring as :in, even if
   no clients are connected. This lets /api/shell-trace show what was
   attempted."
  (let ((photo-ai-lisp::*shell-clients* '()))
    (photo-ai-lisp::shell-trace-clear)
    (photo-ai-lisp::shell-broadcast-input "abc123")
    (let ((snap (photo-ai-lisp::shell-trace-snapshot)))
      (5am:is (= 1 (length snap)))
      (5am:is (eq :in (getf (first snap) :dir)))
      (5am:is (= 6 (getf (first snap) :bytes))))))

(5am:test inject-handler-nil-text-is-empty
  "GET /api/inject with no ?text= should treat it as empty and return
   recipients=0 (no clients in the test suite)."
  (let ((photo-ai-lisp::*shell-clients* '()))
    (photo-ai-lisp::shell-trace-clear)
    (let ((json (photo-ai-lisp::inject-handler nil)))
      (5am:is (search "\"ok\":true" json))
      (5am:is (search "\"recipients\":0" json))
      (5am:is (search "\"bytes\":0" json)))))

(5am:test inject-handler-returns-byte-count
  (let ((photo-ai-lisp::*shell-clients* '()))
    (photo-ai-lisp::shell-trace-clear)
    (let ((json (photo-ai-lisp::inject-handler "echo hi")))
      (5am:is (search "\"bytes\":7" json)))))

(5am:test scrub-for-utf8-replaces-surrogates
  "Lone high/low surrogates map to #\\? so the UTF-8 frame encoder
   in hunchensocket does not choke."
  (let* ((s (coerce (list (code-char #x41)
                          (code-char #xD800)
                          (code-char #xDC00)
                          (code-char #x42))
                    'string))
         (out (photo-ai-lisp::%scrub-for-utf8 s)))
    (5am:is (= 4 (length out)))
    (5am:is (char= #\A (char out 0)))
    (5am:is (char= #\? (char out 1)))
    (5am:is (char= #\? (char out 2)))
    (5am:is (char= #\B (char out 3)))))
