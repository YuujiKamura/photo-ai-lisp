(in-package #:photo-ai-lisp)

;;; Preset registry — the allowlist the UI injects into the live terminal.
;;;
;;; Each preset is a named entry with argv tokens plus an optional
;;; initial input prompt. The UI joins argv with spaces + CR and
;;; postMessages the result into the /shell iframe, where xterm.js
;;; forwards it over /ws/shell into the already-running shell (cmd.exe
;;; on Windows, bash on Unix). No server-side subprocess spawn happens
;;; here — the injected text runs inside the shell the user is already
;;; looking at.
;;;
;;; If :input is non-nil the UI fires it as a follow-up message into
;;; the just-spawned agent (see issue #38 for the broadcast-input flow).
;;;
;;; Contract with the front end:
;;;   preset argv must be a safe command line as typed in the target
;;;   shell. No shell metacharacters beyond what you would type
;;;   intentionally. CR is appended client-side to trigger execution.
;;;
;;; DSL:
;;;   (defpreset <name>
;;;     :argv ("arg0" "arg1" ...)
;;;     :input "初期プロンプト" ; optional, nil for no follow-up
;;;     :group "解析"           ; optional, nil for top-level
;;;     )

(defvar *presets* (make-hash-table :test 'equal)
  "Name (string) → plist (:argv (...) :input string-or-nil :group string-or-nil).
   Populated by DEFPRESET.")

(defvar *preset-order* '()
  "Preset names in insertion order (most recently defined first). DEFPRESET
   pushes new names onto the head; LIST-PRESET-NAMES reverses to yield
   declaration order. REPL redefinition of an existing preset does not
   append again, so the order stays stable across hot-swap.")

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %expand-preset-argv (form)
    "Lower an :argv keyword value into a Lisp expression that yields the
     argv string list.

     Two shapes are supported:
       :argv (\"claude\" \"--foo\")            literal list of strings
       :argv (list (if ...) \"--foo\" ...)     explicit list constructor

     The literal form (plain parenthesized strings) is re-wrapped with
     LIST so that evaluation does not try to funcall the head string.
     Any form whose head is a non-string symbol (e.g. LIST, APPEND,
     QUOTE) is passed through unchanged."
    (cond
      ;; NIL / empty argv — unusual but legal, treat as empty list.
      ((null form) ''())
      ;; Literal list of strings: (\"a\" \"b\").
      ((and (consp form) (stringp (car form)))
       `(list ,@form))
      ;; Assume an already list-producing form (LIST, APPEND, etc.).
      (t form))))

(defmacro defpreset (name &key argv input group)
  "Register a preset under NAME (keyword or string).

   :ARGV is a list of argv tokens to inject into the terminal. Either a
   literal (\"claude\" \"--foo\") or an expression that evaluates to a
   list ((list (if ...) ...)).

   :INPUT is an optional string (or expression evaluating to one, or
   NIL) used as an initial prompt to broadcast into the agent after
   spawn. Defaults to NIL.

   :GROUP is an optional string — if non-nil, the UI buckets the preset
   under a group header of that name (2-level menu). NIL means the
   preset is a top-level button.

   REPL re-evaluation just overwrites the existing entry and preserves
   the preset's original declaration position in *preset-order*."
  (let ((key (string-downcase (string name))))
    `(progn
       (setf (gethash ,key *presets*)
             (list :argv ,(%expand-preset-argv argv)
                   :input ,input
                   :group ,group))
       (unless (member ,key *preset-order* :test #'equal)
         (setf *preset-order* (append *preset-order* (list ,key))))
       ,key)))

(defun find-preset (name)
  "Look up NAME (any case) in the preset registry. Returns the full
   plist (:argv (...) :input ...) or NIL if unknown."
  (gethash (string-downcase (string name)) *presets*))

(defun find-preset-argv (name)
  "argv list for NAME, or NIL if the preset is unknown."
  (let ((entry (find-preset name)))
    (and entry (getf entry :argv))))

(defun find-preset-input (name)
  "Initial input string for NAME, or NIL if the preset has no initial
   prompt (or is unknown)."
  (let ((entry (find-preset name)))
    (and entry (getf entry :input))))

(defun find-preset-group (name)
  "Group label for NAME, or NIL if the preset is top-level (or unknown)."
  (let ((entry (find-preset name)))
    (and entry (getf entry :group))))

(defun list-preset-names ()
  "All registered preset names in declaration order. Defined presets
   missing from *preset-order* (shouldn't happen in practice) get
   sorted to the end so the UI still sees them."
  (let* ((known (remove-if-not (lambda (k) (gethash k *presets*))
                               *preset-order*))
         (known-set (copy-list known))
         (extras '()))
    (maphash (lambda (k _v)
               (declare (ignore _v))
               (unless (member k known-set :test #'equal)
                 (push k extras)))
             *presets*)
    (append known (sort extras #'string<))))

;; ---- bundled presets -----------------------------------------------------
;;
;; Each preset spawns `claude --dangerously-skip-permissions` and then
;; broadcasts an initial prompt (preset.input) describing what the
;; agent should do.  The argv is identical for every entry below — the
;; "what" lives entirely in :input.  See issue #38.
;;
;; Layout (declaration order = UI render order, see *preset-order*):
;;
;;   学習                  (top-level)
;;   施工状況              ┐
;;   出来形管理             │  group "解析"
;;   品質管理              │
;;   その他                ┘
;;   マスタ確認            (top-level)
;;
;; The four 解析 presets share a common footer (chat fallback +
;; master-not-selected hint).  *analyze-footer* keeps the footer in
;; one place and DEF-ANALYZE-PRESET stitches it onto each bias body
;; at macroexpand time so the JSON the UI sees still contains the
;; full prompt — no client-side concatenation, no run-time format.

(defparameter *analyze-footer*
  "- 対象ディレクトリ / 参照マスタ / 種別 / 出力先が不明なら chat で聞け
- マスタ未選択なら「マスタ確認 preset で先に」と案内"
  "Common footer appended to every 解析-group preset's :input. Kept as
   a defparameter so REPL hot-reload of presets.lisp picks up edits
   immediately and every analyze preset rebuilds with the new text.")

(defparameter *claude-argv* '("claude" "--dangerously-skip-permissions")
  "Spawn line shared by every bundled preset. claude CLI with
   permissions skipped because the agent runs inside the same shell
   the user is already supervising via xterm.js.")

(defmacro def-analyze-preset (name bias)
  "Register a 解析-group preset NAME whose initial prompt is BIAS plus
   the shared *analyze-footer*. Expands to a plain DEFPRESET so all
   the order/group/JSON machinery above is reused without a special
   case. NAME is a string (the preset name shown in the sidebar);
   BIAS is a string (the bias line specific to this preset)."
  `(defpreset ,name
     :argv (list "claude" "--dangerously-skip-permissions")
     :group "解析"
     :input (format nil "~a~%~a" ,bias *analyze-footer*)))

(defpreset "学習"
  :argv (list "claude" "--dangerously-skip-permissions")
  :group nil
  :input "photo-reference-build スキルで GT (Excel 一覧 + PDF 写真帳) から reference.json を逆生成しろ。
- ref に出現してマスタに無い語は検索パターン候補としてユーザーに提示して追記の可否を確認しろ
- GT パス / 既存マスタ / 出力先が不明なら chat で聞け、推測で進めるな")

(def-analyze-preset "施工状況"
  "写真区分=施工状況 のバイアスで photo-ai-workflow 全段 (scan → keyword-extract → match-master → report-export) を回せ。施工状況以外の区分が混じったら個別に確認しろ。")

(def-analyze-preset "出来形管理"
  "写真区分=出来形管理 のバイアスで photo-ai-workflow 全段を回せ。寸法/出来形値の写り込みを優先で読み、出来形以外の写真は別群に分離しろ。")

(def-analyze-preset "品質管理"
  "写真区分=品質管理 のバイアスで photo-ai-workflow 全段を回せ。温度管理黒板を検出したら photo-temperature-cycle-resolve で 9 枚サイクルを解決してから match-master 結果を上書きしろ。")

(def-analyze-preset "その他"
  "写真区分のバイアスを掛けず photo-ai-workflow 全段 (AI 抽出 + 決定論判定) を回せ。区分は AI 出力と decisive ルールの合議で決めろ。")

(defpreset "マスタ確認"
  :argv (list "claude" "--dangerously-skip-permissions")
  :group nil
  :input "解析を始める前のドライラン役として動け。
1. masters/ 配下の CSV/Excel を列挙しろ
2. 各マスタを行数・写真区分内訳・種別 top-N でプロファイルしろ
3. ユーザーに「今日の現場で使うマスタはどれか」を選ばせろ
4. 選ばれたマスタを写真区分 × 種別で絞り込み、該当する全行を列挙しろ
5. ギャップ (区分/種別の欠落) を発見したら「学習 preset でマスタを育てて」と案内しろ
連結ツリー整合などの健全性チェックには踏み込むな。あくまで「どのマスタで解析を始めるか」の合意形成だけが役割だ。")

;; ---- hot reload ----------------------------------------------------------

(defvar *reloadable-modules*
  '(:proc :presets :business-ui :term :control :main)
  "Source module keywords that /api/reload can hot-swap. Keys map to
   files under src/ via the naming convention src/<key>.lisp.")

;; Observer registry. Any module that wants to react to a module reload
;; (e.g. control.lisp broadcasting to /ws/control) pushes a function
;; #'(lambda (label) ...) here. reload-handler fans out after a
;; successful reload. Keeping the list here (not in control.lisp)
;; avoids a cycle: the reload layer owns the event, subscribers attach
;; themselves.
(defvar *reload-observers* '())

(defun notify-reload-observers (label)
  "Call every function in *reload-observers* with LABEL. Individual
   observer failures are logged and swallowed so one broken observer
   cannot poison the others."
  (dolist (fn *reload-observers*)
    (handler-case (funcall fn label)
      (error (e)
        (format *error-output* "reload-observer-err: ~a~%" e)
        (finish-output *error-output*)))))

(defun %src-path (key)
  "Pathname to src/<key>.lisp relative to the running image's cwd."
  (merge-pathnames
   (format nil "src/~a.lisp" (string-downcase (symbol-name key)))
   (uiop:getcwd)))

(defun reload-module (key)
  "Reload one source file by keyword (e.g. :presets → src/presets.lisp).
   Returns (:ok :module K :elapsed-ms N). Signals if KEY is not in
   *reloadable-modules* or if the file fails to compile/load."
  (let ((k (intern (string-upcase (string key)) :keyword)))
    (unless (member k *reloadable-modules*)
      (error "module ~a not in *reloadable-modules*" k))
    (let* ((path (%src-path k))
           (start (get-internal-real-time)))
      (unless (uiop:file-exists-p path)
        (error "source file not found: ~a" path))
      (load path)
      (let ((elapsed-ms
              (floor (* 1000 (/ (- (get-internal-real-time) start)
                                internal-time-units-per-second)))))
        (list :ok t :module k :elapsed-ms elapsed-ms)))))

(defun reload-all-modules ()
  "Reload every module in *reloadable-modules* in declared order.
   Returns (:ok :modules (...) :elapsed-ms N)."
  (let ((start (get-internal-real-time)))
    (dolist (k *reloadable-modules*)
      (reload-module k))
    (list :ok t
          :modules *reloadable-modules*
          :elapsed-ms (floor (* 1000 (/ (- (get-internal-real-time) start)
                                        internal-time-units-per-second))))))

(defun reload-handler (module-or-nil)
  "HTTP handler body for /api/reload?module=NAME (nil = all).
   After a successful reload, push a 'reload:<module>' frame to every
   /ws/control listener so browsers hot-swap without an F5."
  (handler-case
      (let* ((result (if (and module-or-nil (plusp (length module-or-nil)))
                         (reload-module module-or-nil)
                         (reload-all-modules)))
             (modules (getf result :modules))
             (mod     (getf result :module))
             (label   (cond
                        (mod     (format nil "~(~a~)" mod))
                        (modules "all")
                        (t       "all"))))
        (notify-reload-observers (format nil "reload:~a" label))
        (format nil
                "{\"ok\":true,\"elapsed_ms\":~a~a}"
                (getf result :elapsed-ms)
                (cond
                  (modules
                   (format nil ",\"modules\":[~{\"~(~a~)\"~^,~}]"
                           modules))
                  (mod
                   (format nil ",\"module\":\"~(~a~)\"" mod))
                  (t ""))))
    (error (e)
      (format nil "{\"ok\":false,\"error\":\"~a\"}"
              (%json-escape (princ-to-string e))))))

;; ---- HTTP handler --------------------------------------------------------

(defun list-presets-handler ()
  "HTTP handler body for GET /api/presets. Returns a JSON array of
   {name, argv, input, group} in declaration order so the UI can render
   buttons dynamically with a stable 2-level grouping.
   input and group are null when the preset has no initial prompt or
   no group header (top-level)."
  (let ((objs
          (loop for name in (list-preset-names)
                for argv = (find-preset-argv name)
                for input = (find-preset-input name)
                for group = (find-preset-group name)
                collect (format nil
                                "{\"name\":\"~a\",\"argv\":[~{\"~a\"~^,~}],\"input\":~a,\"group\":~a}"
                                (%json-escape name)
                                (mapcar #'%json-escape argv)
                                (if input
                                    (format nil "\"~a\"" (%json-escape input))
                                    "null")
                                (if group
                                    (format nil "\"~a\"" (%json-escape group))
                                    "null")))))
    (format nil "[~{~a~^,~}]" objs)))