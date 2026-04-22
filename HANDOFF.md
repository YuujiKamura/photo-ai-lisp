# Handoff — 2026-04-22

## 現在地

- リポ: `C:\Users\yuuji\photo-ai-lisp` (YuujiKamura/photo-ai-lisp)
- HEAD: `f424964` (origin/main 同期済)
- 起動: `bash scripts/demo.sh` で SBCL 立ち上げ、Chrome / Edge があればアプリ窓が自動で開く

## 着手待ち Issues

### #44 IME preedit を visible textarea 方式に戻す (優先 P0)

<https://github.com/YuujiKamura/photo-ai-lisp/issues/44>

- 現状: `term.textarea` を `opacity: 0` で隠して、overlay canvas に JS から preedit を自前描画 (approximate 止まり)
- 修正: composition 中だけ textarea を可視化して color / font / background / caretColor を terminal と揃える。OS IME が real-time に inline 描画してくれる
- 触る範囲: `src/term.lisp:587-661` の IME 結線のみ
- 削る: `term.setPreedit` / `term.clearPreedit` 呼び出し
- 検証: Windows MS-IME / Google 日本語入力で「にほんご」打って real-time 表示確認 (**実機視認はユーザー必須**)
- 受け入れ基準 6 項目は issue 本文
- 工数: 半日〜1日
- これが効けば Phase 2 native embed は不要になる

### #43 LAN 公開時の書込系エンドポイント保護 (優先 P1)

<https://github.com/YuujiKamura/photo-ai-lisp/issues/43>

- 現状: `/api/inject`, `/ws/shell`, `/api/reload` が LAN 公開で RCE 同然 (`/api/eval` のみガード済)
- 段階 1 修正: bind デフォルトを `127.0.0.1` に変更、`BIND=0.0.0.0` でオプトイン。`/api/reload` に localhost ガード追加
- `src/security.lisp` 新設 → `%localhost-p` を `src/live-repl.lisp` から移動
- `tests/security-tests.lisp` 追加
- 受け入れ基準 4 項目は issue 本文

## AI が単独でやれる範囲

- **単独完遂**: Lisp コード / テスト / ドキュメント / security hardening
- **人間視認必須**: IME 挙動の変更は必ず「日本語打って preedit が見えるか」を人間に確認してもらう
- **AI 判定不能**: 日本語 IME UX の快適さ・追従感

## 既知の注意事項

- `asdf:test-system :photo-ai-lisp` の full pass 数は未計測。#44 #43 に着手する前に regression 基準として一度回す
- `src/live-repl.lisp` の `%localhost-p` を `src/security.lisp` に移すとき、live-repl.lisp 側は定義消して参照だけ残す
- ghostty-web は `static/vendor/` に同梱 (coder/ghostty-web 由来)。本家 demo (<https://ghostty.ondis.co>) は CJK commit すら表示しないので、photo-ai-lisp 側の conpty-bridge + CP65001 + VT UTF-8 が既に先行してる

## 参考ファイル

- `BACKLOG.md` — Tier / Phase 状況
- `HANDOVER.md` (2026-04-18) — 上流の設計経緯
- `LESSONS.md` — drift reset 経緯
- `README.md` — ユーザー向け最小版
- `docs/shell-architecture.md` — `/ws/shell` 経路の 5 レイヤ構造
