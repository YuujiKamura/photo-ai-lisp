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

;; ---- regression: bundled presets carry the new content -----------------
;;
;; Team C swapped the 3 legacy presets (hello / skills-list / date) for
;; the 6 production presets that drive the photo-ai pipeline. The tests
;; below pin the contract Team B relies on:
;;   - every preset spawns claude with --dangerously-skip-permissions
;;   - the 4 解析 presets share group "解析" and end with the common
;;     footer
;;   - 学習 and マスタ確認 stay top-level (group=null)
;;   - declaration order matches the menu layout (UI is server-driven)

(defparameter *bundled-preset-names*
  '("学習" "施工状況" "出来形管理" "品質管理" "その他" "マスタ確認")
  "The 6 bundled presets that ship with photo-ai-lisp, in declaration
   order. Pinned here so the regression tests below stay readable.")

(5am:test bundled-presets-share-claude-argv
  "Every bundled preset spawns the same claude CLI with skip-permissions —
   the per-preset behaviour lives entirely in :input."
  (dolist (name *bundled-preset-names*)
    (5am:is (equal '("claude" "--dangerously-skip-permissions")
                   (photo-ai-lisp::find-preset-argv name))
            "preset ~a has wrong argv" name)))

(5am:test bundled-presets-have-non-empty-input
  "Every bundled preset carries an :input string. None should fall back
   to the legacy nil — the new content model assumes a follow-up prompt
   is always broadcast after spawn."
  (dolist (name *bundled-preset-names*)
    (let ((input (photo-ai-lisp::find-preset-input name)))
      (5am:is (stringp input) "preset ~a :input not a string" name)
      (5am:is (plusp (length input)) "preset ~a :input empty" name))))

(5am:test analyze-presets-share-group
  "施工状況 / 出来形管理 / 品質管理 / その他 all live under group 解析."
  (dolist (name '("施工状況" "出来形管理" "品質管理" "その他"))
    (5am:is (equal "解析" (photo-ai-lisp::find-preset-group name))
            "preset ~a expected group 解析" name)))

(5am:test top-level-presets-have-null-group
  "学習 と マスタ確認 はトップレベル (group=nil)。"
  (5am:is (null (photo-ai-lisp::find-preset-group "学習")))
  (5am:is (null (photo-ai-lisp::find-preset-group "マスタ確認"))))

(5am:test analyze-presets-end-with-shared-footer
  "DEF-ANALYZE-PRESET stitches *analyze-footer* onto each bias body so
   the chat-fallback hint and master-not-selected hint are present in
   every 解析 preset. Pinning the footer suffix prevents drift between
   bias edits and the shared text."
  (let ((suffix photo-ai-lisp::*analyze-footer*))
    (dolist (name '("施工状況" "出来形管理" "品質管理" "その他"))
      (let* ((input (photo-ai-lisp::find-preset-input name))
             (tail-start (- (length input) (length suffix))))
        (5am:is (and (>= tail-start 0)
                     (string= input suffix :start1 tail-start))
                "preset ~a does not end with *analyze-footer*" name)))))

(5am:test bundled-presets-declaration-order
  "Menu layout is server-driven — list-preset-names must hand back the
   exact order the spec mandates: 学習 → 4×解析 → マスタ確認."
  (let ((names (photo-ai-lisp::list-preset-names)))
    (5am:is (equal *bundled-preset-names* names)
            "preset order mismatch: got ~a" names)))

(5am:test bundled-presets-emit-group-key-in-json
  "JSON contract: 4 解析 presets surface group=\"解析\", the other 2
   surface group=null. Pinning the count guards both the shape and
   the bucketing distribution."
  (let ((json (photo-ai-lisp::list-presets-handler)))
    (let ((null-count 0)
          (kaiseki-count 0)
          (null-needle "\"group\":null")
          (kaiseki-needle "\"group\":\"解析\"")
          (start 0))
      (loop for pos = (search null-needle json :start2 start)
            while pos do (incf null-count) (setf start (1+ pos)))
      (setf start 0)
      (loop for pos = (search kaiseki-needle json :start2 start)
            while pos do (incf kaiseki-count) (setf start (1+ pos)))
      (5am:is (= 2 null-count)
              "expected 2 \"group\":null entries, got ~a" null-count)
      (5am:is (= 4 kaiseki-count)
              "expected 4 \"group\":\"解析\" entries, got ~a"
              kaiseki-count))))
