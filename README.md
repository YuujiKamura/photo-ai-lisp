<img width="1555" height="1075" alt="image" src="https://github.com/user-attachments/assets/b65e17ea-4d2e-4360-a422-c355f09aa5fb" />

# photo-ai-lisp

工事写真まわりの作業を 1 画面でまとめて回すためのローカルアプリ。左にプリセットボタン、右にターミナルが並んでいて、ボタンを押すとターミナルへコマンドが流し込まれる。

## 動かすのに要るもの

事前に入れておくもの:

- **SBCL 2.6 以降** — Steel Bank Common Lisp 本体
  - 入手: <https://www.sbcl.org/platform-table.html>
  - PATH に入っていれば起動スクリプトがそのまま認識する
  - 入っていなくても、`C:\Program Files\Steel Bank Common Lisp\`、`%USERPROFILE%\SBCLLocal\...`、`%LOCALAPPDATA%\Programs\...`、`C:\sbcl\` など代表的な導入先は自動で探す
  - 上記以外の場所に入れた場合は `SBCL=/path/to/sbcl.exe bash scripts/demo.sh` のように env var で渡す
- **Quicklisp** — Common Lisp のパッケージマネージャ
  - 入手: <https://www.quicklisp.org/beta/>（ページの手順どおり `curl -O` → `sbcl --load quicklisp.lisp` → `(quicklisp-quickstart:install)`）
  - 終わると `~/quicklisp/setup.lisp` が出来ている状態になる
- **git** — このリポジトリを `git clone` するため

OS:

- **Windows 10 / 11**（Git Bash 推奨。コマンドプロンプトでも可）
- **macOS / Linux**（任意のターミナル）

## 起動

Git Bash や macOS / Linux のターミナルから:

```bash
cd ~/photo-ai-lisp && bash scripts/demo.sh
```

Windows のコマンドプロンプトから:

```
cd /d %USERPROFILE%\photo-ai-lisp && scripts\demo.cmd
```

**しばらく待つとアプリウィンドウが自動で立ち上がる**（タブもアドレスバーも無い独立窓）。止めるときは起動したターミナルで `Ctrl-C`。

アプリ窓が出てこない環境 (Chrome も Edge も入っていないなど) のときだけ、起動ログに出る `SERVER http://localhost:8090/` を手動で開けばよい。自動起動が邪魔なときは `NO_APP_WINDOW=1 bash scripts/demo.sh`。

## 画面の見かた

- **左サイドバー** — 先頭に `agent on / off` インジケータ、その下にプリセットボタン一覧
  - `起動` グループ: `claude` / `gemini` / `codex` のランチャー (1 クリックで起動)
  - `解析` グループ + 単発プロンプト系: claude に初期プロンプトを流し込むボタン（agent off のときは disable）
  - `画面クリア`: `/exit` + `cls` を送って画面をリセット（常時有効）
- **右ペイン** — ターミナル 1 本。ボタンを押すとここに直接コマンドが入る。

ボタンを押すたびに裏でプロセスが立ち上がるわけではなく、画面に見えているターミナル 1 本で順番に動くので、何が走っているかは常に目で追える。

## ボタン（プリセット）の足しかた

### 種類

プリセットは **3 種類**あり、`:argv` と `:agent` の組み合わせで自動的に振り分けられる:

| 種類       | `:argv` | `:agent`  | 挙動                                                             |
|-----------|---------|-----------|-----------------------------------------------------------------|
| launcher  | あり     | あり      | argv をそのまま打って agent 起動。`agentRunning=true` に倒す        |
| prompt    | なし     | あり      | paste + 時差 Enter で input を agent の chat に投入 (agent off は無効)|
| shell     | あり     | なし      | argv を直接シェルに打つ。`/exit` 始まりなら `agentRunning=false`    |

### ソースで追加

`src/presets.lisp` に 1 つ追記して保存:

```lisp
;; claude に投げるプロンプトボタン (prompt type)
(defpreset "施工状況"
  :agent "claude"
  :group "解析"
  :input "写真区分=施工状況 のバイアスで photo-ai-workflow 全段を回せ。…")

;; 独自 agent のランチャーを足す場合 (launcher type)
(defpreset "my-agent"
  :agent "my-agent"
  :group "起動"
  :argv (list "my-agent" "--some-flag"))
```

書いた順がそのままボタンの並び順。アプリを止めずに変更を反映したいときは、アプリ内のターミナルから:

```
curl http://localhost:8090/api/reload?module=presets
```

### 実行中に API で追加・編集・削除

サーバは live-edit エンドポイントも持っていて、ファイルを触らずに増減できる。エージェントに任せる時もこの口を叩かせる:

```bash
# 新規追加
curl -X POST http://localhost:8090/api/presets/new/<name> \
  -H 'Content-Type: application/json' \
  --data-binary '{"agent":"claude","input":"..."}'

# 部分更新 (任意フィールドのみ)
curl -X POST http://localhost:8090/api/presets/rewrite/<name> \
  -H 'Content-Type: application/json' \
  --data-binary '{"input":"..."}'

# 削除
curl -X POST http://localhost:8090/api/presets/delete/<name>

# 現在の状態を src/presets-live.lisp に焼いて永続化
curl -X POST http://localhost:8090/api/presets/deploy
```

`deploy` が走るまでの編集は in-memory のみ。`src/presets-live.lisp` は ASDF が `presets.lisp` の後に読み込む overlay なので、deploy 後は再起動しても live 状態が復元される。overlay を捨てれば工場出荷 (`presets.lisp`) に戻る。

## ライセンス

MIT
