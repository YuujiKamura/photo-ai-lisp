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
;; Post-picker schema (direct launch): the bundle is now split into
;; three kinds, tagged via (hasArgv, hasAgent, hasInput):
;;
;;   LAUNCHER   argv + agent         — spawn the agent executable
;;                                     directly (claude / gemini /
;;                                     codex). No prompt.
;;   PROMPT     agent + input        — paste+submit INPUT into the
;;              (no argv)              running agent. UI gates these
;;                                     on agentRunning=true.
;;   SHELL      argv (no agent)      — type a literal shell command.
;;
;; Tests below pin:
;;   - 3 launchers: claude / gemini / codex (argv set, agent set,
;;     group \"起動\", no input)
;;   - 7 claude-agent prompt presets (agent=\"claude\", no argv)
;;   - 1 shell preset: 画面クリア (argv=/exit, no agent)
;;   - declaration order matches the menu layout (server-driven)

(defparameter *bundled-launcher-names*
  '("claude" "gemini" "codex")
  "Launcher presets, in declaration order.")

(defparameter *bundled-prompt-preset-names*
  '("学習" "施工状況" "出来形管理" "品質管理" "その他" "マスタ確認" "マスタ棚卸し")
  "Claude-agent prompt presets, in declaration order.")

(defparameter *bundled-export-preset-names*
  '("写真帳 pdf" "写真帳 excel")
  "photo-ai-go バイナリを叩く出力系 shell preset。DEFPRESET の key は
   STRING-DOWNCASE されるので ASCII は小文字で書く。")

(defparameter *bundled-preset-names*
  (append *bundled-launcher-names*
          *bundled-prompt-preset-names*
          *bundled-export-preset-names*
          '("画面クリア"))
  "All bundled presets in declaration order (menu layout).")

(5am:test bundled-launchers-have-argv-and-agent
  "Each launcher carries both :argv (the spawn command) and :agent
   (the identity for the agentRunning flag), grouped under \"起動\",
   with no :input."
  (dolist (name *bundled-launcher-names*)
    (let ((argv  (photo-ai-lisp::find-preset-argv  name))
          (agent (photo-ai-lisp::find-preset-agent name))
          (group (photo-ai-lisp::find-preset-group name))
          (input (photo-ai-lisp::find-preset-input name)))
      (5am:is (and (listp argv) (plusp (length argv)))
              "launcher ~a should have non-empty argv" name)
      (5am:is (equal name agent)
              "launcher ~a should self-identify via :agent" name)
      (5am:is (equal "起動" group)
              "launcher ~a should live under group 起動" name)
      (5am:is (null input)
              "launcher ~a should not carry an :input prompt" name))))

(5am:test claude-prompt-presets-are-prompt-only
  "Each claude-agent prompt preset declares :agent \"claude\", leaves
   :argv empty (prompt-only), and carries a non-empty :input."
  (dolist (name *bundled-prompt-preset-names*)
    (5am:is (equal "claude" (photo-ai-lisp::find-preset-agent name))
            "prompt preset ~a expected agent=claude" name)
    (5am:is (null (photo-ai-lisp::find-preset-argv name))
            "prompt preset ~a should have no literal argv" name)
    (let ((input (photo-ai-lisp::find-preset-input name)))
      (5am:is (stringp input) "preset ~a :input not a string" name)
      (5am:is (plusp (length input)) "preset ~a :input empty" name))))

(5am:test screen-clear-preset-is-shell-mode
  "画面クリア is the one bundled shell-mode preset: no :agent, a
   literal /exit argv, and a cls follow-up. /exit closes claude if
   it's running; cmd.exe ignores /exit harmlessly otherwise. No
   pick-agent reference — the picker layer was retired."
  (5am:is (null (photo-ai-lisp::find-preset-agent "画面クリア")))
  (5am:is (equal '("/exit") (photo-ai-lisp::find-preset-argv "画面クリア")))
  (let ((input (photo-ai-lisp::find-preset-input "画面クリア")))
    (5am:is (stringp input))
    (5am:is (search "cls" input))
    (5am:is (not (search "pick-agent" input))
            "画面クリア must not re-introduce the picker")))

(5am:test analyze-presets-share-group
  "施工状況 / 出来形管理 / 品質管理 / その他 all live under group 解析."
  (dolist (name '("施工状況" "出来形管理" "品質管理" "その他"))
    (5am:is (equal "解析" (photo-ai-lisp::find-preset-group name))
            "preset ~a expected group 解析" name)))

(5am:test top-level-presets-have-null-group
  "学習 / マスタ確認 / マスタ棚卸し / 画面クリア はトップレベル。"
  (dolist (name '("学習" "マスタ確認" "マスタ棚卸し" "画面クリア"))
    (5am:is (null (photo-ai-lisp::find-preset-group name))
            "preset ~a should be top-level (group=nil)" name)))

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
   exact order the spec mandates: 学習 → 4×解析 → マスタ確認 →
   マスタ棚卸し → セレクターに戻る."
  (let ((names (photo-ai-lisp::list-preset-names)))
    (5am:is (equal *bundled-preset-names* names)
            "preset order mismatch: got ~a" names)))

(defun %count-json-matches (json needle)
  "Count non-overlapping occurrences of NEEDLE in JSON."
  (loop with start = 0
        for pos = (search needle json :start2 start)
        while pos
        count pos
        do (setf start (1+ pos))))

(5am:test bundled-presets-emit-group-key-in-json
  "JSON group distribution for the bundled layout:
     3 under 起動  (launchers)
     4 under 解析  (analyze prompts)
     2 under 出力  (photo-ai-go PDF / Excel)
     4 null        (学習 / マスタ確認 / マスタ棚卸し / 画面クリア)"
  (let ((json (photo-ai-lisp::list-presets-handler)))
    (5am:is (= 4 (%count-json-matches json "\"group\":null")))
    (5am:is (= 3 (%count-json-matches json "\"group\":\"起動\"")))
    (5am:is (= 4 (%count-json-matches json "\"group\":\"解析\"")))
    (5am:is (= 2 (%count-json-matches json "\"group\":\"出力\"")))))

(5am:test bundled-presets-emit-agent-key-in-json
  "JSON agent distribution:
     1 claude launcher + 7 claude prompts = 8 agent=\"claude\"
     1 gemini launcher                      = 1 agent=\"gemini\"
     1 codex launcher                       = 1 agent=\"codex\"
     2 出力 shell + 1 画面クリア shell      = 3 agent=null"
  (let ((json (photo-ai-lisp::list-presets-handler)))
    (5am:is (= 8 (%count-json-matches json "\"agent\":\"claude\"")))
    (5am:is (= 1 (%count-json-matches json "\"agent\":\"gemini\"")))
    (5am:is (= 1 (%count-json-matches json "\"agent\":\"codex\"")))
    (5am:is (= 3 (%count-json-matches json "\"agent\":null")))))
