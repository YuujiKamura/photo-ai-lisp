(in-package #:photo-ai-lisp/tests)

(5am:def-suite presets-suite :description "preset registry")
(5am:in-suite presets-suite)

(5am:test defpreset-registers-argv
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (photo-ai-lisp::defpreset "sample" "echo" "hi")
    (5am:is (equal '("echo" "hi")
                   (photo-ai-lisp::find-preset "sample")))))

(5am:test defpreset-case-insensitive
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (photo-ai-lisp::defpreset "MIXED-Case" "ls")
    (5am:is (equal '("ls") (photo-ai-lisp::find-preset "mixed-case")))
    (5am:is (equal '("ls") (photo-ai-lisp::find-preset "MIXED-CASE")))))

(5am:test find-preset-unknown-returns-nil
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (5am:is (null (photo-ai-lisp::find-preset "does-not-exist")))))

(5am:test list-preset-names-sorted
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (photo-ai-lisp::defpreset "zebra" "x")
    (photo-ai-lisp::defpreset "alpha" "y")
    (photo-ai-lisp::defpreset "mango" "z")
    (5am:is (equal '("alpha" "mango" "zebra")
                   (photo-ai-lisp::list-preset-names)))))

(5am:test list-presets-handler-returns-json-array
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (photo-ai-lisp::defpreset "one" "echo" "1")
    (photo-ai-lisp::defpreset "two" "echo" "2")
    (let ((json (photo-ai-lisp::list-presets-handler)))
      (5am:is (search "\"name\":\"one\"" json))
      (5am:is (search "\"name\":\"two\"" json))
      (5am:is (char= #\[ (char json 0)))
      (5am:is (char= #\] (char json (1- (length json))))))))
