(in-package #:photo-ai-lisp/tests)

(5am:def-suite live-repl-suite :description "HTTP /api/eval")
(5am:in-suite live-repl-suite)

(5am:test live-eval-arithmetic
  (let ((r (photo-ai-lisp::live-eval "(+ 40 2)")))
    (5am:is (equal "42" (getf r :ok)))))

(5am:test live-eval-string
  (let ((r (photo-ai-lisp::live-eval "(concatenate 'string \"a\" \"b\")")))
    (5am:is (search "ab" (getf r :ok)))))

(5am:test live-eval-defpreset-adds-to-registry
  "Eval a defpreset form over 'HTTP' (just live-eval directly) and
   the new preset is visible via find-preset."
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (photo-ai-lisp::live-eval
     "(defpreset \"eval-test\" \"echo\" \"alive\")")
    (5am:is (equal '("echo" "alive")
                   (photo-ai-lisp::find-preset "eval-test")))))

(5am:test live-eval-read-error-returned-as-json-error
  (let ((r (photo-ai-lisp::live-eval "(this is not balanced")))
    (5am:is (null (getf r :ok)))
    (5am:is (plusp (length (getf r :error))))))

(5am:test live-eval-runtime-error-caught
  (let ((r (photo-ai-lisp::live-eval "(error \"kaboom\")")))
    (5am:is (null (getf r :ok)))
    (5am:is (search "kaboom" (getf r :error)))))
