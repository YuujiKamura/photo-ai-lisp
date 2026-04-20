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

プリセットボタンをクリックすると `/api/run/:name` が走り、結果が「リザルト」タブに出る。

## エンドポイント

| | |
|---|---|
| `GET /` | メイン UI |
| `GET /api/masters` | `masters/*.csv` を JSON で返す |
| `GET /api/presets` | 登録済みプリセット一覧 |
| `GET /api/run/:name` | プリセット実行（stdout と exit_code を JSON で返す） |
| `GET /cases` | ケース一覧（JSON） |
| `GET /cases/:id` | ケース詳細（HTML） |

## プリセットの追加

`src/presets.lisp` の `defpreset` で登録。

```lisp
(defpreset "hello"
  "cmd.exe" "/c" "echo hello from photo-ai-lisp")
```

REPL に走らせれば即反映（サーバ再起動不要）。`rm` `del` `format` `shutdown` `drop` を含む argv は登録時に拒否される。

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
