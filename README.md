# photo-ai-lisp

工事写真パイプラインのローカルオーケストレータ。ターミナル表示 + マスタ CSV + スキル群を 1 パッケージで携帯・配布することがゴール。

シリーズ（同ドメインを言語違いで書いた並走リポ）の 1 つ。位置付けと方針は [#20](https://github.com/YuujiKamura/photo-ai-lisp/issues/20)、UI 構成は [#21](https://github.com/YuujiKamura/photo-ai-lisp/issues/21)。

## 必要なもの

- SBCL 2.6+
- Quicklisp（`~/quicklisp/setup.lisp` があること）
- Windows（Git Bash） or Unix

## 起動

```bash
bash scripts/demo.sh
```

`SERVER http://localhost:8090/` と出たらブラウザで開く。`Ctrl-C` で停止。

Windows コマンドプロンプトからは `scripts\demo.cmd`。

## 画面

- 左サイドバー：工種マスタ（`masters/*.csv` から自動ロード）、プリセットボタン
- 右上タブ：ガイド / マスタツリー / リザルト / 問診票
- 右下：ghostty-web を iframe で埋め込むペイン

プリセットボタンをクリックすると、argv を joins space + CR した文字列が下のターミナル iframe に `postMessage` で注入され、そのまま実行される（サーバ側サブプロセスは起動せず、見えているシェルで動く）。

## エンドポイント

| | |
|---|---|
| `GET /` | メイン UI |
| `GET /api/masters` | `masters/*.csv` を JSON で返す |
| `GET /api/presets` | 登録済みプリセット一覧（UI が起動時に読む） |
| `GET /api/shell-trace` | /ws/shell を流れた直近 100 フレームの ring buffer |
| `GET /api/reload?module=<key>` | サーバ無停止で `src/<key>.lisp` 再読込 |
| `GET /shell` | 内蔵ターミナル（xterm.js + /ws/shell） |
| `GET /cases` | ケース一覧（JSON） |
| `GET /cases/:id` | ケース詳細（HTML） |

## プリセットの追加

`src/presets.lisp` の `defpreset` で登録。

```lisp
(defpreset "hello" "echo" "hello" "from" "photo-ai-lisp")
```

argv は「そのままターミナルに打つ安全なコマンド」の想定。

## ホットリロード

サーバ停止なしでコード変更を反映する手段が 2 つ：

1. `curl http://localhost:8090/api/reload?module=presets`
   → `src/presets.lisp` を `load` し直す（10〜50ms）。プリセット追加・修正が即 UI に反映
   → `module=all` で全 `*reloadable-modules*` を順次再読込

2. `scripts/demo.sh` は起動時に swank を port 4005 で立てる（失敗しても続行）。
   Emacs から `M-x slime-connect localhost 4005` で接続してそのまま式評価が可能。
   `NO_SWANK=1` で無効化。

## ディレクトリ

```
src/          Common Lisp 本体
static/       HTML/CSS/JS（photo-ai-rust/web/index.html の移植スケルトン）
masters/      工種マスタ CSV（携帯する中身）
scripts/      demo 起動スクリプト
docs/         仕様・検証ログ
tests/        FiveAM テスト
```

## 出典

- UI 構造は [photo-ai-rust/web/index.html](https://github.com/YuujiKamura/photo-ai-rust/blob/main/web/index.html) から移植
- ターミナル描画は [ghostty-web](https://github.com/coder/ghostty-web) を iframe で同梱予定
- スキル群は [photo-ai-skills](https://github.com/YuujiKamura/photo-ai-skills) を subprocess 呼び出し予定

## ライセンス

MIT
