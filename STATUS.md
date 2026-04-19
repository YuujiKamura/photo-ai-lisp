# Project Status: photo-ai-lisp

## 2026-04-19 状況認識

### 1. CI/品質管理 (Current Baseline)
- **厳密なLintの導入**: `scripts/lint.lisp` により、`asdf:load-system` 時に発生する全ての `WARNING`（スタイル警告、再定義、未使用変数等）をエラーとして扱う運用を開始。
- **クリーンなコードベース**: 重複していた `%json-escape` の削除、`spawn-child` の引数シグネチャの統一（全て `&key` へ）、テスト内の未使用変数の解消を完了。
- **GitHub Actions**: 高速（1分以内）かつ、警告のない「内容の伴ったグリーン」を維持。

- **Pipeline Core (Atoms P-04 - P-08)**: 完了。
  - `defpipeline` マクロによる静的なワークフロー定義と登録。
  - `run-pipeline` エンジンによる、出力から入力への自動スレッディング（Threading）。
  - ステップ失敗時の即時停止（Halt）と、詳細な実行履歴（`pipeline-result`）の記録。
  - 未定義スキル等の異常系に対する、堅牢なエラーハンドリング。

- **Control Plane Integration (Atom 17.1-17.4)**: 完了。
  - `src/cp-protocol.lisp`: コマンド生成とレスポンスパースを実装 (17.1)。
  - `src/cp-client.lisp`: `websocket-driver` による接続・同期送信基盤を実装 (17.2)。
  - `src/pipeline-cp.lisp`: 常駐エージェントへの指示出し（`INPUT`）と完了待機ロジックを実装 (17.3)。
  - **The Purge (Atom 17.4)**: `src/term.lisp` および `src/agent.lisp` から OS プロセスへの直接依存（fork/exec）を排除。Lisp 側は純粋な司令塔（CP クライアント）として刷新。

### 3. 次の課題 (Next Actions)
- **Atom 17.5: iframe 連携の配線**: `business-ui` のターミナル pane を、Lisp 経由ではなく直接 `ghostty-web` (Node.js) またはデーモンを向くように調整。
- **実機結合試験**: 実際に `Deckpilot` や `ghostty-web` デーモンを立てた状態での Pipeline 完走確認。
- **Open Questionsの解消**: エージェントの分離ポリシー確定。

## 開発の指針
- **Warnings are Errors**: コード変更時は必ず `sbcl --load scripts/lint.lisp` を通すこと。
- **Atom Integrity**: 1つのAtomでテストが通らない場合は、関連するAtomを慎重に組み合わせて「常にグリーン」を保つこと。
