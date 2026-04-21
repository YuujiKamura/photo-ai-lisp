(in-package #:photo-ai-lisp/tests)

(5am:def-suite presets-suite :description "preset registry")
(5am:in-suite presets-suite)

(5am:test defpreset-registers-argv
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal))
        (photo-ai-lisp::*preset-order* '()))
    (photo-ai-lisp::defpreset "sample" :argv '("echo" "hi"))
    (5am:is (equal '("echo" "hi")
                   (photo-ai-lisp::find-preset-argv "sample")))
    (5am:is (null (photo-ai-lisp::find-preset-input "sample")))
    (5am:is (null (photo-ai-lisp::find-preset-group "sample")))))

(5am:test defpreset-stores-input-keyword
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal))
        (photo-ai-lisp::*preset-order* '()))
    (photo-ai-lisp::defpreset "with-input"
                              :argv '("claude")
                              :input "初期プロンプト")
    (5am:is (equal '("claude")
                   (photo-ai-lisp::find-preset-argv "with-input")))
    (5am:is (equal "初期プロンプト"
                   (photo-ai-lisp::find-preset-input "with-input")))))

(5am:test defpreset-case-insensitive
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal))
        (photo-ai-lisp::*preset-order* '()))
    (photo-ai-lisp::defpreset "MIXED-Case" :argv '("ls"))
    (5am:is (equal '("ls") (photo-ai-lisp::find-preset-argv "mixed-case")))
    (5am:is (equal '("ls") (photo-ai-lisp::find-preset-argv "MIXED-CASE")))))

(5am:test find-preset-returns-full-plist
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal))
        (photo-ai-lisp::*preset-order* '()))
    (photo-ai-lisp::defpreset "plist-shape"
                              :argv '("a" "b")
                              :input "p"
                              :group "解析")
    (let ((entry (photo-ai-lisp::find-preset "plist-shape")))
      (5am:is (equal '("a" "b") (getf entry :argv)))
      (5am:is (equal "p" (getf entry :input)))
      (5am:is (equal "解析" (getf entry :group))))))

(5am:test find-preset-unknown-returns-nil
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal))
        (photo-ai-lisp::*preset-order* '()))
    (5am:is (null (photo-ai-lisp::find-preset "does-not-exist")))
    (5am:is (null (photo-ai-lisp::find-preset-argv "does-not-exist")))
    (5am:is (null (photo-ai-lisp::find-preset-input "does-not-exist")))
    (5am:is (null (photo-ai-lisp::find-preset-group "does-not-exist")))))

(5am:test list-preset-names-declaration-order
  "Team C (#38): list-preset-names now returns declaration order so the
   frontend can render groups in the order defpreset was issued. The
   old alphabetical contract is intentionally broken — the UI needs
   to control visual order from presets.lisp."
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal))
        (photo-ai-lisp::*preset-order* '()))
    (photo-ai-lisp::defpreset "zebra" :argv '("x"))
    (photo-ai-lisp::defpreset "alpha" :argv '("y"))
    (photo-ai-lisp::defpreset "mango" :argv '("z"))
    (5am:is (equal '("zebra" "alpha" "mango")
                   (photo-ai-lisp::list-preset-names)))))

(5am:test defpreset-redefinition-preserves-order
  "REPL redefinition must not reshuffle the menu — hot-reload of
   presets.lisp reruns every DEFPRESET form, so redefining the same
   name should leave *preset-order* alone."
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal))
        (photo-ai-lisp::*preset-order* '()))
    (photo-ai-lisp::defpreset "first" :argv '("a"))
    (photo-ai-lisp::defpreset "second" :argv '("b"))
    (photo-ai-lisp::defpreset "first" :argv '("a2"))
    (5am:is (equal '("first" "second")
                   (photo-ai-lisp::list-preset-names)))
    (5am:is (equal '("a2")
                   (photo-ai-lisp::find-preset-argv "first")))))

(5am:test defpreset-group-keyword-stored
  "#38 Team C — :group keyword stores a string or nil."
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal))
        (photo-ai-lisp::*preset-order* '()))
    (photo-ai-lisp::defpreset "top" :argv '("x"))
    (photo-ai-lisp::defpreset "under-kaiseki" :argv '("y") :group "解析")
    (5am:is (null (photo-ai-lisp::find-preset-group "top")))
    (5am:is (equal "解析"
                   (photo-ai-lisp::find-preset-group "under-kaiseki")))))

(5am:test list-presets-handler-returns-json-array
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal))
        (photo-ai-lisp::*preset-order* '()))
    (photo-ai-lisp::defpreset "one" :argv '("echo" "1"))
    (photo-ai-lisp::defpreset "two" :argv '("echo" "2") :input "go")
    (let ((json (photo-ai-lisp::list-presets-handler)))
      (5am:is (search "\"name\":\"one\"" json))
      (5am:is (search "\"name\":\"two\"" json))
      ;; Every entry carries an "input" key.
      (5am:is (search "\"input\":null" json))
      (5am:is (search "\"input\":\"go\"" json))
      ;; Every entry now also carries a "group" key.
      (5am:is (search "\"group\":null" json))
      (5am:is (char= #\[ (char json 0)))
      (5am:is (char= #\] (char json (1- (length json))))))))

(5am:test list-presets-handler-emits-group-key
  "#38 Team C — JSON array surfaces \"group\" as null for top-level
   presets and as a quoted string for grouped ones."
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal))
        (photo-ai-lisp::*preset-order* '()))
    (photo-ai-lisp::defpreset "flat" :argv '("a"))
    (photo-ai-lisp::defpreset "kid" :argv '("b") :group "解析")
    (let ((json (photo-ai-lisp::list-presets-handler)))
      ;; null group for top-level.
      (5am:is (search "\"name\":\"flat\"" json))
      (5am:is (search "\"group\":null" json))
      ;; string group for child.
      (5am:is (search "\"name\":\"kid\"" json))
      (5am:is (search "\"group\":\"解析\"" json)))))

(5am:test list-presets-handler-preserves-declaration-order
  "JSON preset order matches DEFPRESET call order. Frontend groups
   presets visually in the order they first appear in this array, so
   a stable order is a UI contract."
  (let ((photo-ai-lisp::*presets* (make-hash-table :test 'equal))
        (photo-ai-lisp::*preset-order* '()))
    (photo-ai-lisp::defpreset "zzz" :argv '("a"))
    (photo-ai-lisp::defpreset "aaa" :argv '("b"))
    (let* ((json (photo-ai-lisp::list-presets-handler))
           (pz (search "\"name\":\"zzz\"" json))
           (pa (search "\"name\":\"aaa\"" json)))
      (5am:is (numberp pz))
      (5am:is (numberp pa))
      (5am:is (< pz pa)))))

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

(5am:test bundled-presets-emit-group-key-in-json
  "#38 Team C — every bundled preset must surface a \"group\" key
   through list-presets-handler. The 3 legacy presets (hello,
   skills-list, date) are top-level so their group is null. Content
   swap with real :group values lands in a later commit — this test
   guards the schema shape, not the specific group labels."
  (let ((json (photo-ai-lisp::list-presets-handler)))
    (let ((count 0)
          (needle "\"group\":null")
          (start 0))
      (loop for pos = (search needle json :start2 start)
            while pos do
              (incf count)
              (setf start (1+ pos)))
      (5am:is (>= count 3)
              "expected >=3 \"group\":null occurrences, got ~a" count))))
