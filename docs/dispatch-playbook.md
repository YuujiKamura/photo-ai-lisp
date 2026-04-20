# Dispatch Playbook

Hub (Sonnet/Opus) が dispatch 運用を回すための運用手順書。

## 1. Hub 役の責任範囲

- **やること**: テンプレ選び、パラメータ埋め、launch、管理役委任、完了検収。
- **やらないこと**: プロダクトコード編集、調査実行、最終判断 (Opus エスカレーション)。

## 2. テンプレート選定フロー

```text
Q. Dispatch の目的は？
├── 実装・修正 (Feature/Fix) ──> templates/brief-implementation.md
├── 調査・再現 (Investigate) ──> templates/brief-investigation.md
├── タスク分解 (Planning)   ──> templates/brief-breakdown.md
└── 他セッション監視 (Babysit) ──> templates/brief-manager-role.md
```

## 3. launch の標準手順

```powershell
# デフォルトで Gemini を使用。cwd を忘れずに指定
deckpilot launch gemini "path/to/brief.md" --cwd C:/Users/yuuji/photo-ai-lisp

# submit_failed_stuck が出たら sleep 5 → deckpilot send で再送
```

## 4. 承認プロンプト対応

- **Gemini**: `Allow execution of ...?` 
  - `deckpilot send <sess> "2"` (Allow for this session) を推奨。
- **Claude CLI**: `Yes, I trust this folder?` 
  - `1` (Yes) を初回のみ手動、または `deckpilot send`。
- **Claude OMC**: 通常不要 (bypass permissions)。

## 5. 管理役 (Manager Role) の使いどころ

- **SBCL Debugger Trap**: REPL 待機で Thinking が無限ループする場合、管理役が `taskkill` する。
- **高頻度承認**: `Allow execution` が多発する場合、管理役が `2` を送り続ける。
- **Auto-approvals Regression**: deckpilot の自動承認が効かなくなった場合 (regression)、管理役が介入する。

## 6. Stall (失速) 判定と復旧

- **5 分超同じ Thinking**: `deckpilot show` で内容確認。
- **Shell awaiting input**: 子プロセス (Debugger 等) 疑い。`tasklist` + `taskkill` でプロセスを殺す。
- **deckpilot daemon 不調**: `deckpilot shutdown` + 再起動。

## 7. Opus エスカレーション基準

以下は Hub (Sonnet) では判断せず、Opus へエスカレーションすること：
- KEEP/ARCHIVE の最終判定。
- Roadmap の大幅な変更・承認。
- 難解な Regression の原因特定 (直感が必要な場合)。
- 新 Feature の Scope 決定。

## 8. テンプレートの更新サイクル

- 新しい型のブリーフを書いた日は、そのブリーフをテンプレに吸収するタスクを翌日の Hub 初動に入れること。
- 本 Playbook 自体がその仕組み (Self-improvement) の成果物である。
