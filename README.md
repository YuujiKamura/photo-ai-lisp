<img width="1487" height="1189" alt="image" src="https://github.com/user-attachments/assets/8494fde0-bf00-42d3-8493-27e25e263cfa" />


# photo-ai-lisp

工事写真まわりの作業を 1 画面でまとめて回すためのローカルアプリ。左に工種マスタとよく使うボタン、右にターミナルが並んでいて、ボタンを押すとターミナルへコマンドが流し込まれる。

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

- **左サイドバー**: 工種マスタ + プリセットボタン
- **右上**: ガイド / マスタツリー / リザルト / 問診票 のタブ
- **右下**: ターミナル（ボタンを押すとここにコマンドが流し込まれる）

ボタンを押すたびに裏でプロセスが立ち上がるわけではなく、画面に見えているターミナル 1 本で順番に動くので、何が走っているかは常に目で追える。

## ボタン（プリセット）の足しかた

`src/presets.lisp` に 1 つ追記して保存:

```lisp
(defpreset "施工状況"
  :argv  (list "claude" "--dangerously-skip-permissions")
  :group "解析"
  :input "写真区分=施工状況 のバイアスで photo-ai-workflow 全段を回せ。…")
```

- `:argv` … クリックしたときにターミナルへ流れる 1 行
- `:input` … その次に続けて送る文字列（省略可）
- `:group` … サイドバーで束ねる見出し名（省略すると最上段）

書いた順がそのままボタンの並び順。アプリを止めずに変更を反映したいときは、下の URL をアプリ内のターミナルから叩く:

```
curl http://localhost:8090/api/reload?module=presets
```

## ライセンス

MIT
