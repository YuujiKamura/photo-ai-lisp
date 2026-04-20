# Handoff — 2026-04-20 21:10

## 現在地
- リポ: `C:\Users\yuuji\photo-ai-lisp`
- HEAD: `2a95c96 fix(term): make %normalize-child-input idempotent over consecutive CRs` (origin/main と同期予定)
- 直近 3 コミット:
  - `2a95c96` term: `%normalize-child-input` を連続 CR に対して idempotent に。`CRCR…` を単一 CR へ畳み込む。
  - `e5a19b7` proc: child stdio に `:external-format :latin-1` を明示。無視される `:element-type` は撤去。
  - `de778f7` shell: `/ws/shell` で起動する `cmd.exe` を `conpty-bridge` 経由に統一。picker レース解消。

## テスト状況 (2026-04-20 21:08 の計測)
- `asdf:test-system :photo-ai-lisp` → 110 checks / **97 pass / 7 fail / 6 skip**。
- 7 failures はすべて `PIPELINE-INVOKE-VIA-CP-*` (JSON / INTERACTION)。**Team 2 が並列対応中**のスコープ。Team 1 では触らない。
- 6 skip は既知の Windows 環境条件 (`SPAWN-CHILD-UNIX-ECHO`, `SHELL-ECHO-ROUND-TRIP`, `PROC-*`)。

## 動いてるもの
- `scripts/demo.sh` — SBCL + Swank 4005、port 8090。
- `tools/conpty-bridge/conpty-bridge.exe` (Go)。`src/term.lisp::%shell-argv` が bridge wrap を経由。
- `/api/inject`, `/ws/control` (live-reload), vendored ghostty-web。

### E2E チェーン (de778f7 / 2a95c96 で確定)
ブラウザ `/shell` → picker (`1+Enter`) → `claude` CLI REPL 起動 が通る。証拠 screenshot: `.dispatch/task-d-after1.png` (過去セッション)。

## 既知の残課題 / 非自明な運用状況
- **port 8090 ゾンビ socket 残存**: `netstat -ano` で `PID 7344` が `LISTENING` + 多数の `CLOSE_WAIT` を保持。`taskkill` 不能。OS reboot まで解放不能。
- **port 8091 は別プロセスが listen 中**: 現時点 (21:10) で `PID 41316` が `0.0.0.0:8091` を保持。`scripts/demo.lisp` を再起動したい場合は 8090 も 8091 も占有済みである前提で port 番号を可変にしろ。
- **CP pipeline テスト (7 件) が fail**: `src/pipeline-cp.lisp` / `tests/pipeline-cp-tests.lisp` 周辺。Team 2 スコープ。Team 1 は触るな。
- `photo-ai-lisp-track-b` sibling は **git worktree (branch `track-b/ansi-parser`)** として登録済み。`git worktree list` で可視。消さない。
- `.claude/worktrees/agent-a03e3777`, `agent-a10cb0d3` は locked worktree。触るな。

## 今回 (Team 1 クリーンアップ) の変更
- `.gitignore` に `demo/node_modules/`, `demo/_*.mjs`, `demo.log` を追加 (puppeteer 用 scratch)。
- `static/index.html:141` `runPreset` の CRLF 送信を単一 LF に (`%normalize-child-input` の LF→CR 変換に任せて defense-in-depth)。
- `scripts/demo_v.lisp` (untracked、`demo.lisp` の port 8091 variant) を削除。port はファイル複製で持つべきでなく、必要時に起動時引数/一時編集で切り替える運用 (HANDOFF に記載)。
- `tests/proc-bridge-io-tests.lisp` (untracked) を削除。`photo-ai-lisp.asd` に未登録の ad-hoc diagnostics。Windows では `spawn-child` ベースの類似テストが既に skip 対象。
- `tests/verify-task-c.lisp` (untracked) を削除。既完了 Task C の手動 runner。`asdf:test-system` で代替可能。

## 次セッションの再開手順
1. `netstat -ano | grep -E ':8090|:8091'` で port 状況を確認。
2. 8090 ゾンビが消えていれば `scripts/demo.sh`。残っていれば一時的に別 port で `scripts/demo.lisp` の引数を書き換え (コミットしない)。
3. Team 2 の CP pipeline 修正結果 (`src/pipeline-cp.lisp`, `tests/pipeline-cp-tests.lisp`) をレビュー。
4. 110 / 97 / 7 / 6 baseline を維持。

## Team 1 スコープ外 (触るな)
- `src/` 以下すべて
- `tests/pipeline-cp-tests.lisp`, `tests/cp-*.lisp`
- `tests/term-tests.lisp`, `tests/inject-e2e-scenario.lisp`
- `tools/conpty-bridge/` 以下
- 他の worktree の中身
