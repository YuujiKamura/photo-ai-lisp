<img width="1519" height="1032" alt="image" src="https://github.com/user-attachments/assets/8f721815-c462-4880-ae01-c5d6ec94046d" />

# photo-ai-lisp

工事写真まわりの作業を 1 画面でまとめて回すためのローカルアプリ。ブラウザで開くと、左に工種マスタとよく使うボタン、右にターミナルが並んでいて、ボタンを押すとターミナルへコマンドが流し込まれる。

## 動かすのに要るもの

- SBCL 2.6 以降
- Quicklisp（`~/quicklisp/setup.lisp` が置いてあること）
- Windows（Git Bash）か Unix 系
- ブラウザ（Chrome / Edge / Firefox どれでも）

## 起動

Git Bash や macOS / Linux のターミナルから:

```bash
cd ~/photo-ai-lisp && bash scripts/demo.sh
```

Windows のコマンドプロンプトから:

```
cd /d %USERPROFILE%\photo-ai-lisp && scripts\demo.cmd
```

しばらく待って `SERVER http://localhost:8090/` と出たら、そのアドレスをブラウザで開く。止めるときは起動したターミナルで `Ctrl-C`。

### アプリ風の独立ウィンドウで開く（任意）

ブラウザのタブやアドレスバーを消して「アプリっぽい」見た目にしたいときは Chrome を `--app` モードで起動する:

```bash
chrome --app=http://localhost:8090/ --window-size=1280,780
```

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

書いた順がそのままボタンの並び順。サーバを止めずに変更を反映したいときは、下の URL をブラウザで 1 回踏む:

```
http://localhost:8090/api/reload?module=presets
```

## ライセンス

MIT
