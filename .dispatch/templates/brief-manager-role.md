# [ROLE-HANDOVER] {{MANAGER_SESS}} → {{TARGET_SESS}} 管理役

## 前提
- {{MANAGER_SESS}} は自身のメインタスクを完了または完了直前。
- 監視対象: `{{TARGET_SESS}}` (別エージェント)。{{TARGET_TASK_DESCRIPTION}}。

## 新しい役割
君は `{{TARGET_SESS}}` を監視・Babysit する Hub 管理役に転じる。
Claude メイン人格は高次判断に専念する。

## やること
1. **定期観測**: `deckpilot show {{TARGET_SESS}} --tail 40` を {{POLLING_INTERVAL}} 秒ごとに実行。
2. **承認・入力介入**:
   - `Allow execution of ...?` → `deckpilot send {{TARGET_SESS}} "2"` (安全な場合のみ)。
   - 不審なコマンド (`rm -rf`, `git push`) は `3` で拒絶。
3. **Stall 判定と復旧**:
   - Thinking が {{STALL_LIMIT}} 分継続 → `taskkill` または指示送り。
4. **完了判定**: `DISPATCH-DONE` 出力または成果物の commit。
5. **最終レポート**: メインタスクのレポートに追記。

## 成果物
- {{MAIN_REPORT}} への追記

## 制約 (破るな)
- `git push` 禁止
- 監視対象の worktree を直接編集しない
- 完了時 `MANAGER-ROLE-DONE` を出力して停止

## 期待所要時間
{{MIN_TIME}}〜{{MAX_TIME}} 分/時間
