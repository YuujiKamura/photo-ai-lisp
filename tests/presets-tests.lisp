(in-package #:photo-ai-lisp/tests)

(5am:def-suite presets-suite :description "preset registry")
(5am:in-suite presets-suite)

(5am:test defpreset-registers-argv
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (photo-ai-lisp::defpreset "sample" :argv '("echo" "hi"))
    (5am:is (equal '("echo" "hi")
                   (photo-ai-lisp::find-preset-argv "sample")))
    (5am:is (null (photo-ai-lisp::find-preset-input "sample")))))

(5am:test defpreset-stores-input-keyword
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (photo-ai-lisp::defpreset "with-input"
                              :argv '("claude")
                              :input "初期プロンプト")
    (5am:is (equal '("claude")
                   (photo-ai-lisp::find-preset-argv "with-input")))
    (5am:is (equal "初期プロンプト"
                   (photo-ai-lisp::find-preset-input "with-input")))))

(5am:test defpreset-case-insensitive
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (photo-ai-lisp::defpreset "MIXED-Case" :argv '("ls"))
    (5am:is (equal '("ls") (photo-ai-lisp::find-preset-argv "mixed-case")))
    (5am:is (equal '("ls") (photo-ai-lisp::find-preset-argv "MIXED-CASE")))))

(5am:test find-preset-returns-full-plist
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (photo-ai-lisp::defpreset "plist-shape"
                              :argv '("a" "b")
                              :input "p")
    (let ((entry (photo-ai-lisp::find-preset "plist-shape")))
      (5am:is (equal '("a" "b") (getf entry :argv)))
      (5am:is (equal "p" (getf entry :input))))))

(5am:test find-preset-unknown-returns-nil
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (5am:is (null (photo-ai-lisp::find-preset "does-not-exist")))
    (5am:is (null (photo-ai-lisp::find-preset-argv "does-not-exist")))
    (5am:is (null (photo-ai-lisp::find-preset-input "does-not-exist")))))

(5am:test list-preset-names-sorted
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (photo-ai-lisp::defpreset "zebra" :argv '("x"))
    (photo-ai-lisp::defpreset "alpha" :argv '("y"))
    (photo-ai-lisp::defpreset "mango" :argv '("z"))
    (5am:is (equal '("alpha" "mango" "zebra")
                   (photo-ai-lisp::list-preset-names)))))

(5am:test list-presets-handler-returns-json-array
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal)))
    (photo-ai-lisp::defpreset "one" :argv '("echo" "1"))
    (photo-ai-lisp::defpreset "two" :argv '("echo" "2") :input "go")
    (let ((json (photo-ai-lisp::list-presets-handler)))
      (5am:is (search "\"name\":\"one\"" json))
      (5am:is (search "\"name\":\"two\"" json))
      ;; Every entry carries an "input" key.
      (5am:is (search "\"input\":null" json))
      (5am:is (search "\"input\":\"go\"" json))
      (5am:is (char= #\[ (char json 0)))
      (5am:is (char= #\] (char json (1- (length json))))))))

;; ---- regression: bundled presets keep their argv semantics --------------
;;
;; Team C replaces the preset *content* later in a separate commit; this
;; suite is Team A's contract that the DSL refactor did not silently
;; drop argv tokens for the 3 legacy presets, and that :input defaults
;; to nil for all of them.

(5am:test legacy-hello-preset-argv-intact
  (5am:is (equal '("echo" "hello" "from" "photo-ai-lisp")
                 (photo-ai-lisp::find-preset-argv "hello")))
  (5am:is (null (photo-ai-lisp::find-preset-input "hello"))))

(5am:test legacy-skills-list-preset-argv-intact
  (let ((argv (photo-ai-lisp::find-preset-argv "skills-list")))
    (5am:is (= 2 (length argv)))
    (5am:is (member (first argv) '("dir" "ls") :test #'equal))
    (5am:is (null (photo-ai-lisp::find-preset-input "skills-list")))))

(5am:test legacy-date-preset-argv-intact
  (let ((argv (photo-ai-lisp::find-preset-argv "date")))
    (5am:is (= 2 (length argv)))
    (5am:is (member (first argv) '("echo" "date") :test #'equal))
    (5am:is (null (photo-ai-lisp::find-preset-input "date")))))

(5am:test bundled-presets-emit-input-key-in-json
  "Regardless of Team C's later content swap, every bundled preset
   must surface an \"input\" key through list-presets-handler so Team B
   can rely on its presence for every entry."
  (let ((json (photo-ai-lisp::list-presets-handler)))
    (dolist (name '("hello" "skills-list" "date"))
      (5am:is (search (format nil "\"name\":\"~a\"" name) json)
              "preset ~a missing from JSON" name))
    ;; Each bundled preset currently has :input nil, so we must see at
    ;; least 3 "input":null occurrences. Count them with a simple loop.
    (let ((count 0)
          (needle "\"input\":null")
          (start 0))
      (loop for pos = (search needle json :start2 start)
            while pos do
              (incf count)
              (setf start (1+ pos)))
      (5am:is (>= count 3)
              "expected >=3 \"input\":null occurrences, got ~a" count))))
