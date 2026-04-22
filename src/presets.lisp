(in-package #:photo-ai-lisp)

;;; Preset registry — the allowlist the UI injects into the live terminal.
;;;
;;; Each preset is a named entry with argv tokens plus an optional
;;; initial input prompt. The UI joins argv with spaces + CR and
;;; postMessages the result into the /shell iframe, where ghostty-web
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

(defmacro defpreset (name &key argv input group agent)
  "Register a preset under NAME (keyword or string).

   :AGENT is an optional string identifying an interactive TUI agent
   launched via pick-agent.cmd: \"claude\" / \"gemini\" / \"codex\".
   When set, the UI derives the picker digit and uses the paste+Enter
   submit protocol. When NIL, the preset targets the raw shell and
   :ARGV + single-Enter injection is used.

   :ARGV is a list of argv tokens to inject when :AGENT is NIL (raw
   shell mode). Either a literal (\"...\" \"...\") or an expression
   evaluating to a list. Ignored (and should be NIL) when :AGENT is
   set — the UI computes the picker digit itself.

   :INPUT is an optional string for the follow-up prompt. Agent-mode
   presets use it as the chat prompt; shell-mode presets use it as a
   follow-up shell command after :ARGV runs.

   :GROUP buckets the preset under a group header of that name; NIL
   makes it a top-level button.

   REPL re-evaluation overwrites the entry and preserves declaration
   order in *preset-order*."
  (let ((key (string-downcase (string name))))
    `(progn
       (setf (gethash ,key *presets*)
             (list :argv ,(%expand-preset-argv argv)
                   :input ,input
                   :group ,group
                   :agent ,agent))
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

(defun find-preset-agent (name)
  "Agent identifier (\"claude\"/\"gemini\"/\"codex\") or NIL if the
   preset is shell-mode (or unknown)."
  (let ((entry (find-preset name)))
    (and entry (getf entry :agent))))

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
;;   マスタ棚卸し          (top-level)
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

(defmacro def-analyze-preset (name bias)
  "Register a 解析-group preset NAME whose initial prompt is BIAS plus
   the shared *analyze-footer*. Expands to a plain DEFPRESET so all
   the order/group/JSON machinery above is reused without a special
   case. NAME is a string (the preset name shown in the sidebar);
   BIAS is a string (the bias line specific to this preset).

   The preset targets the claude agent — the UI handles picker-digit
   spawn and paste+Enter submit automatically."
  `(defpreset ,name
     :agent "claude"
     :group "解析"
     :input (format nil "~a~%~a" ,bias *analyze-footer*)))

;; Reset the registry on every load of this file so hot-reload replaces
;; the bundled set atomically. Without this, removed DEFPRESET forms
;; leave orphan entries in *presets* / *preset-order* after reload.
(clrhash *presets*)
(setf *preset-order* '())

;; ---- agent launchers -----------------------------------------------
;; Direct-spawn presets (argv + agent). Replaces pick-agent.cmd's
;; "press N then Enter" pattern: one click per agent, no middle step.
;;   - :agent "X" marks the preset as a launcher; UI flips
;;     agentRunning=true after the cold-start delay so prompt presets
;;     enable themselves.
;;   - :argv is the actual shell command the terminal types.

(defpreset "claude"
  :agent "claude"
  :group "起動"
  :argv (list "claude" "--dangerously-skip-permissions"))

(defpreset "gemini"
  :agent "gemini"
  :group "起動"
  :argv (list "gemini"))

(defpreset "codex"
  :agent "codex"
  :group "起動"
  :argv (list "codex"))

;; ---- prompt presets (require an agent running) ---------------------

(defpreset "学習"
  :agent "claude"
  :group nil
  :input "~/photo-ai-skills/photo-reference-build/SKILL.md を開いて、その手順で GT (Excel 一覧 + PDF 写真帳) から reference.json を逆生成しろ。
- ref に出現してマスタに無い語は検索パターン候補としてユーザーに提示して追記の可否を確認しろ
- GT パス / 既存マスタ / 出力先が不明なら chat で聞け、推測で進めるな")

(def-analyze-preset "施工状況"
  "~/photo-ai-skills/photo-ai-workflow/SKILL.md を開け。写真区分=施工状況 のバイアスで全段 (scan → keyword-extract → match-master → report-export) を回せ。施工状況以外の区分が混じったら個別に確認しろ。各段のスキルは ~/photo-ai-skills/photo-{scan,keyword-extract,match-master,report-export}/SKILL.md に個別に置いてある。")

(def-analyze-preset "出来形管理"
  "~/photo-ai-skills/photo-ai-workflow/SKILL.md を開け。写真区分=出来形管理 のバイアスで全段を回せ。寸法/出来形値の写り込みを優先で読み、出来形以外の写真は別群に分離しろ。")

(def-analyze-preset "品質管理"
  "~/photo-ai-skills/photo-ai-workflow/SKILL.md を開け。写真区分=品質管理 のバイアスで全段を回せ。温度管理黒板を検出したら ~/photo-ai-skills/photo-temperature-cycle-resolve/SKILL.md の手順で 9 枚サイクルを解決してから match-master 結果を上書きしろ。")

(def-analyze-preset "その他"
  "~/photo-ai-skills/photo-ai-workflow/SKILL.md を開け。写真区分のバイアスを掛けず全段 (AI 抽出 + 決定論判定) を回せ。区分は AI 出力と decisive ルールの合議で決めろ。")

(defpreset "マスタ確認"
  :agent "claude"
  :group nil
  :input "解析を始める前のドライラン役として動け。
1. masters/ 配下の CSV/Excel を列挙しろ
2. 各マスタを行数・写真区分内訳・種別 top-N でプロファイルしろ
3. ユーザーに「今日の現場で使うマスタはどれか」を選ばせろ
4. 選ばれたマスタを写真区分 × 種別で絞り込み、該当する全行を列挙しろ
5. ギャップ (区分/種別の欠落) を発見したら「学習 preset でマスタを育てて」と案内しろ
連結ツリー整合などの健全性チェックには踏み込むな。あくまで「どのマスタで解析を始めるか」の合意形成だけが役割だ。")

(defpreset "マスタ棚卸し"
  :agent "claude"
  :group nil
  :input "masters/ を機械的に棚卸ししろ。以下のコマンドを順に実行し、結果の転記だけが仕事だ。推論・探索・健全性チェックは禁止。

1. Bash `ls -la masters/` で実在ファイルを確認
2. Bash `find . -maxdepth 4 -type f \\( -name '*.csv' -o -name '*.xlsx' -o -name '*.xls' \\) -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/target/*'` でリポジトリ全体のマスタ候補を列挙
3. 各候補に Bash `file <path>; wc -l <path>` を回し encoding と行数を確定
4. CSV は Read で先頭 20 行まで開き、1 行目をスキーマとして抜き出せ
5. Markdown テーブル (path | rows | format | header) で 1 枚にまとめ、末尾に期待カラム (写真区分 / 種別) を持たないマスタをギャップとして列挙
6. ユーザーに「このマスタで進めるか、学習 preset で育てるか」を 1 行で問え")

;; ---- export (photo-ai-go 呼び出し) ----------------------------------
;; 解析で得た中間 JSON (photo-ai-go の analyze が <folder>/result.json に
;; 吐く) から PDF / Excel の写真帳を生成する shell preset。バイナリは
;; 兄弟リポジトリ ~/photo-ai-go/ に置いてある前提。%USERPROFILE% を使う
;; ことでユーザー名を決め打ちせずに cmd.exe のセッション内で絶対パスに
;; 解決される (CLAUDE.md の「ハードコードパス禁止 / 動的解決徹底」準拠)。
;;
;; 現状 result.json は photo-ai-go 側の analyze が産むフォーマット。
;; claude 解析群の出力とは直接つながっていないので、claude 解析 →
;; photo-ai-go で再スキャン、か、photo-ai-go の analyze で一発、
;; のどちらかでまず result.json を作ってから押す。

(defpreset "写真帳 pdf"
  :argv (list "%USERPROFILE%\\photo-ai-go\\photo-ai.exe"
              "export" "pdf" "result.json")
  :group "出力")

(defpreset "写真帳 excel"
  :argv (list "%USERPROFILE%\\photo-ai-go\\photo-ai.exe"
              "export" "excel" "result.json")
  :group "出力")

;; ---- screen clear ---------------------------------------------------
;; 画面クリア — shell-layer preset (agent=nil).
;; /exit は claude のスラッシュコマンドで、claude 実行中ならセッション
;; を閉じて cmd に戻る。cmd プロンプトでは未知コマンドとして fail する
;; だけで無害なので、agent 起動中/非起動どちらで押しても最終的に画面
;; がクリーンになる。「画面をリセットする 1 ボタン」という素直な名前
;; に寄せた — 実装的には /exit + cls。
(defpreset "画面クリア"
  :argv (list "/exit")
  :group nil
  :input "cls")

;; ---- hot reload ----------------------------------------------------------

(defvar *reloadable-modules*
  '(:proc :presets :presets-live :business-ui :term :control :main)
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
   {name, argv, input, group, agent} in declaration order so the UI can
   render buttons dynamically with a stable 2-level grouping.
   input / group / agent are null when absent."
  (let ((objs
          (loop for name in (list-preset-names)
                for argv = (find-preset-argv name)
                for input = (find-preset-input name)
                for group = (find-preset-group name)
                for agent = (find-preset-agent name)
                collect (format nil
                                "{\"name\":\"~a\",\"argv\":[~{\"~a\"~^,~}],\"input\":~a,\"group\":~a,\"agent\":~a}"
                                (%json-escape name)
                                (mapcar #'%json-escape argv)
                                (if input
                                    (format nil "\"~a\"" (%json-escape input))
                                    "null")
                                (if group
                                    (format nil "\"~a\"" (%json-escape group))
                                    "null")
                                (if agent
                                    (format nil "\"~a\"" (%json-escape agent))
                                    "null")))))
    (format nil "[~{~a~^,~}]" objs)))

;; ---- live mutation API ---------------------------------------------------
;;
;; NEW / REWRITE / DELETE / DEPLOY fan into these helpers.  Each mutator
;; fires a reload:business-ui frame on /ws/control so the sidebar polls
;; the refreshed /api/presets immediately, skipping the 2 s poll tick.
;;
;; DEPLOY writes src/presets-live.lisp — a file whose ASDF load order
;; is *after* presets.lisp.  At load time it CLRHASH-es the registry
;; and reinstalls every entry, so deploy-then-restart reproduces the
;; live state exactly.  Absent/empty file means the factory bundle in
;; presets.lisp is canonical.

(defun %notify-presets-changed ()
  "Broadcast a reload:business-ui frame so the sidebar re-fetches
   /api/presets without waiting for the 2 s poll."
  (notify-reload-observers "reload:business-ui"))

(defun add-preset-entry (name argv &key input group agent)
  "Install (or overwrite) NAME in the registry and push a reload
   notification. ARGV is a list of strings; INPUT, GROUP, AGENT are
   strings or NIL. Returns NAME in canonical (lowercased) form."
  (let ((key (string-downcase (string name))))
    (setf (gethash key *presets*)
          (list :argv argv :input input :group group :agent agent))
    (unless (member key *preset-order* :test #'equal)
      (setf *preset-order* (append *preset-order* (list key))))
    (%notify-presets-changed)
    key))

(defun rewrite-preset-entry (name &key (argv nil argv-p)
                                       (input nil input-p)
                                       (group nil group-p)
                                       (agent nil agent-p))
  "Partial update. Only fields marked supplied are changed. Errors if
   NAME is not registered. Returns the canonical key."
  (let* ((key (string-downcase (string name)))
         (entry (gethash key *presets*)))
    (unless entry
      (error "preset not found: ~a" name))
    (setf (gethash key *presets*)
          (list :argv  (if argv-p  argv  (getf entry :argv))
                :input (if input-p input (getf entry :input))
                :group (if group-p group (getf entry :group))
                :agent (if agent-p agent (getf entry :agent))))
    (%notify-presets-changed)
    key))

(defun remove-preset-entry (name)
  "Drop NAME from both *presets* and *preset-order*, then broadcast.
   Errors if NAME is unknown so callers can surface a 404."
  (let ((key (string-downcase (string name))))
    (unless (gethash key *presets*)
      (error "preset not found: ~a" name))
    (remhash key *presets*)
    (setf *preset-order* (remove key *preset-order* :test #'equal))
    (%notify-presets-changed)
    key))

;; ---- deploy (serialise current state to src/presets-live.lisp) -----------

(defun %escape-lisp-string (s)
  "Return an S-expression-safe rendering of string S, e.g.
   \"hello\\\"world\" for input hello\"world. PRIN1-TO-STRING on a
   string yields exactly that with correct escaping of \\ and \"."
  (prin1-to-string (or s "")))

(defun %emit-defpreset (name entry stream)
  "Write one DEFPRESET form rebuilding NAME from ENTRY to STREAM.
   ENTRY is the plist stored in *presets* (:argv :input :group :agent).
   Emits every non-nil field; launchers have both :argv and :agent
   (argv spawns the executable, agent identifies which running
   process to flip the agentRunning flag for)."
  (format stream "(defpreset ~a~%" (%escape-lisp-string name))
  (let ((argv (getf entry :argv)))
    (when argv
      (format stream "  :argv (list~{ ~a~})~%"
              (mapcar #'%escape-lisp-string argv))))
  (let ((agent (getf entry :agent)))
    (when agent
      (format stream "  :agent ~a~%" (%escape-lisp-string agent))))
  (let ((group (getf entry :group)))
    (if group
        (format stream "  :group ~a~%" (%escape-lisp-string group))
        (format stream "  :group nil~%")))
  (let ((input (getf entry :input)))
    (if input
        (format stream "  :input ~a)~%~%" (%escape-lisp-string input))
        (format stream "  :input nil)~%~%"))))

(defun deploy-presets ()
  "Serialise the current live state to src/presets-live.lisp. The file
   is loaded after presets.lisp at startup (see asd), so a deploy
   survives restart. Returns (:ok :path P :count N)."
  (let ((path (merge-pathnames "src/presets-live.lisp" (uiop:getcwd)))
        (names (list-preset-names)))
    (with-open-file (stream path :direction :output
                                 :if-exists :supersede
                                 :if-does-not-exist :create
                                 :external-format :utf-8)
      (format stream ";;; AUTO-GENERATED by POST /api/presets  (method DEPLOY).~%")
      (format stream ";;; Live snapshot of *presets* at deploy time. Re-running DEPLOY~%")
      (format stream ";;; rewrites this file in full. Delete to fall back to the~%")
      (format stream ";;; factory bundle in presets.lisp.~%~%")
      (format stream "(in-package #:photo-ai-lisp)~%~%")
      (format stream "(clrhash *presets*)~%")
      (format stream "(setf *preset-order* '())~%~%")
      (dolist (n names)
        (%emit-defpreset n (gethash n *presets*) stream)))
    (list :ok t :path (namestring path) :count (length names))))

;; ---- HTTP dispatcher for /api/presets[/<verb>[/<name>]] ------------------

(defun %preset-path-segments (uri)
  "Split the path after /api/presets into its verb and name segments.
   URI comes from HUNCHENTOOT:SCRIPT-NAME which already percent-decodes
   the path, so Japanese segment names arrive as real characters and
   MUST NOT be url-decoded again (that crashes on non-ASCII).
   Returns (VALUES VERB NAME) where each is a string or NIL.
   Examples:
     /api/presets                      → (nil  nil)
     /api/presets/new/smoke-one        → (\"new\"     \"smoke-one\")
     /api/presets/deploy               → (\"deploy\"  nil)
     /api/presets/delete/マスタ確認    → (\"delete\"  \"マスタ確認\")"
  (let* ((prefix "/api/presets")
         (plen (length prefix)))
    (unless (and (>= (length uri) plen)
                 (string= uri prefix :end1 plen))
      (return-from %preset-path-segments (values nil nil)))
    (when (= (length uri) plen)
      (return-from %preset-path-segments (values nil nil)))
    (unless (char= (char uri plen) #\/)
      (return-from %preset-path-segments (values nil nil)))
    (let* ((rest (subseq uri (1+ plen)))
           (q    (position #\? rest))
           (path (if q (subseq rest 0 q) rest))
           (slash (position #\/ path)))
      (if slash
          (values (subseq path 0 slash)
                  (let ((tail (subseq path (1+ slash))))
                    (and (plusp (length tail)) tail)))
          (values path nil)))))

(defun %parse-preset-body ()
  "Read the raw POST body and parse it as JSON. Returns a hash-table
   or NIL when the body is empty/unparsable."
  (let ((raw (hunchentoot:raw-post-data :force-text t)))
    (when (and raw (plusp (length raw)))
      (handler-case (shasht:read-json raw)
        (error () nil)))))

(defun %json-get (table key)
  "Fetch KEY (string) from shasht-parsed TABLE, or NIL if absent."
  (and (hash-table-p table) (gethash key table)))

(defun %argv-from-json (val)
  "Coerce VAL (shasht-parsed) into a list of strings for :argv. Accepts
   a JSON array; returns NIL for anything else."
  (cond
    ((null val) nil)
    ((vectorp val) (coerce val 'list))
    ((listp val) val)
    (t nil)))

(defun %string-or-nil (val)
  "Return VAL as a string, or NIL if VAL is NIL / :null / absent."
  (cond
    ((or (null val) (eq val :null)) nil)
    ((stringp val) val)
    (t (princ-to-string val))))

(defun %preset-json-response (name extra)
  "Build a {\"ok\":true,\"name\":...,...EXTRA} JSON body. EXTRA is a
   plist of (\"key\" \"jsonvalue\" ...) pre-rendered."
  (with-output-to-string (s)
    (format s "{\"ok\":true,\"name\":~a" (%escape-lisp-string (or name "")))
    (loop for (k v) on extra by #'cddr
          do (format s ",\"~a\":~a" k v))
    (format s "}")))

(defun %preset-error-response (code message)
  (setf (hunchentoot:return-code*) code)
  (format nil "{\"ok\":false,\"error\":~a}" (%escape-lisp-string message)))

(defun preset-new-handler (name)
  "Body of POST /api/presets/new/<name>.
   Body JSON: either {agent:\"claude\"|...} (TUI preset) or
             {argv:[\"...\",...]} (raw-shell preset). Both may set
             input and group."
  (unless (and name (plusp (length name)))
    (return-from preset-new-handler
      (%preset-error-response 400 "name required")))
  (let* ((body  (%parse-preset-body))
         (argv  (%argv-from-json (%json-get body "argv")))
         (input (%string-or-nil (%json-get body "input")))
         (group (%string-or-nil (%json-get body "group")))
         (agent (%string-or-nil (%json-get body "agent"))))
    (unless (or agent argv)
      (return-from preset-new-handler
        (%preset-error-response 400
         "either agent (\"claude\"/\"gemini\"/\"codex\") or argv (JSON array of strings) required")))
    (handler-case
        (let ((key (add-preset-entry name argv
                                     :input input
                                     :group group
                                     :agent agent)))
          (%preset-json-response key '()))
      (error (e)
        (%preset-error-response 500 (princ-to-string e))))))

(defun preset-rewrite-handler (name)
  "Body of POST /api/presets/rewrite/<name>. Partial update: any field
   omitted from the body is left untouched. Supports argv, input,
   group, agent."
  (unless (and name (plusp (length name)))
    (return-from preset-rewrite-handler
      (%preset-error-response 400 "name required")))
  (let* ((body (%parse-preset-body))
         (has-argv  (and body (nth-value 1 (gethash "argv"  body))))
         (has-input (and body (nth-value 1 (gethash "input" body))))
         (has-group (and body (nth-value 1 (gethash "group" body))))
         (has-agent (and body (nth-value 1 (gethash "agent" body)))))
    (unless (or has-argv has-input has-group has-agent)
      (return-from preset-rewrite-handler
        (%preset-error-response 400 "no fields to rewrite (supply argv, input, group, or agent)")))
    (handler-case
        (let* ((args (append (when has-argv  (list :argv  (%argv-from-json (gethash "argv" body))))
                             (when has-input (list :input (%string-or-nil (gethash "input" body))))
                             (when has-group (list :group (%string-or-nil (gethash "group" body))))
                             (when has-agent (list :agent (%string-or-nil (gethash "agent" body))))))
               (key (apply #'rewrite-preset-entry name args)))
          (%preset-json-response key '()))
      (error (e)
        (%preset-error-response 400 (princ-to-string e))))))

(defun preset-delete-handler (name)
  "Body of method DELETE on /api/presets/<name>."
  (unless (and name (plusp (length name)))
    (return-from preset-delete-handler
      (%preset-error-response 400 "name required")))
  (handler-case
      (let ((key (remove-preset-entry name)))
        (%preset-json-response key '()))
    (error (e)
      (%preset-error-response 404 (princ-to-string e)))))

(defun preset-deploy-handler ()
  "Body of method DEPLOY on /api/presets. Writes presets-live.lisp."
  (handler-case
      (let* ((r (deploy-presets))
             (path (getf r :path))
             (count (getf r :count)))
        (format nil "{\"ok\":true,\"path\":~a,\"count\":~a}"
                (%escape-lisp-string path) count))
    (error (e)
      (%preset-error-response 500 (princ-to-string e)))))

(defun %presets-dispatch ()
  "Prefix dispatcher for /api/presets[/<verb>[/<name>]].
   The first path segment after /api/presets is the verb:
     GET  /api/presets                 → list-presets-handler
     POST /api/presets/new/<name>      → preset-new-handler
     POST /api/presets/rewrite/<name>  → preset-rewrite-handler
     POST /api/presets/delete/<name>   → preset-delete-handler
     POST /api/presets/deploy          → preset-deploy-handler

   Hunchentoot rejects non-standard HTTP verbs (NEW / REWRITE / DEPLOY)
   at parse time, so the verb lives in the URL where curl and humans
   can still read it directly."
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (let* ((method (hunchentoot:request-method hunchentoot:*request*))
         (uri    (hunchentoot:script-name  hunchentoot:*request*)))
    (multiple-value-bind (verb name) (%preset-path-segments uri)
      (cond
        ;; GET /api/presets — list
        ((and (eq method :get) (null verb))
         (list-presets-handler))
        ;; POST mutations
        ((eq method :post)
         (cond
           ((and (equal verb "new")     name) (preset-new-handler     name))
           ((and (equal verb "rewrite") name) (preset-rewrite-handler name))
           ((and (equal verb "delete")  name) (preset-delete-handler  name))
           ((equal verb "deploy")             (preset-deploy-handler))
           (t (%preset-error-response
               404
               (format nil "unknown preset verb: ~a (name=~a)"
                       verb name)))))
        (t
         (%preset-error-response
          405
          (format nil "method ~a not allowed on ~a" method uri)))))))