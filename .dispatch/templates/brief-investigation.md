# [HUB-DISPATCH] {{TITLE}} (調査・Bisect)

## プロジェクト
{{REPO_PATH}}
ブランチ: {{BRANCH_POLICY}}

## 参照
{{RELEVANT_ISSUES_FILES_BRIEFS}}

## ゴール
{{GOAL_ONE_PARAGRAPH}}

## やること
1. **再現手順の確立**: {{STEP_1_REPRODUCTION}}
2. **調査・探索**: {{STEP_2_INVESTIGATION}}
3. **原因特定と修正方針の提示**: {{STEP_3_ROOT_CAUSE}}
4. **調査レポート作成**: {{STEP_4_REPORTING}}

## 成果物
- {{REPORTS_FILES_DOCS}}

## 制約 (破るな)
- `git push` 禁止
- プロダクトコードの不用意な修正禁止 (調査・レポート優先)
- commit は調査レポート作成のみに留める
- 承認レベル: 2 (Session-wide)
- 完了時 `DISPATCH-DONE` を出力して停止

## 期待所要時間
{{MIN_TIME}}〜{{MAX_TIME}} 分/時間
