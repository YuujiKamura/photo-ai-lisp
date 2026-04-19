# Project Status: photo-ai-lisp

## 2026-04-19 状況認識

### 1. CI/品質管理 (Current Baseline)
- **厳密なLintの導入**: `scripts/lint.lisp` により、`asdf:load-system` 時に発生する全ての `WARNING`（スタイル警告、再定義、未使用変数等）をエラーとして扱う運用を開始。
- **クリーンなコードベース**: 重複していた `%json-escape` の削除、`spawn-child` の引数シグネチャの統一（全て `&key` へ）、テスト内の未使用変数の解消を完了。
- **GitHub Actions**: 高速（1分以内）かつ、警告のない「内容の伴ったグリーン」を維持。

### 2. 進捗状況 (Atom Landing)
- **Business UI (Atoms 01-07)**: 完了。
  - `/`, `/cases`, `/cases/:id` のルーティングとハンドラが配線済み。
- **Pipeline (Atoms 01-03)**: 完了。
  - スキル登録機能が着陸。
- **Control Plane Integration (Atom 17.1-17.3)**: 完了。
  - `src/cp-protocol.lisp`: コマンド生成とレスポンスパースを実装 (17.1)。
  - `src/cp-client.lisp`: `websocket-driver` による接続・同期送信基盤を実装 (17.2)。
  - `src/pipeline-cp.lisp`: 常駐エージェントへの指示出し（`INPUT`）と完了待機（`TAIL` ループによる `DONE|ERROR` 判定）のコアロジックを実装 (17.3)。

### 3. 次の課題 (Next Actions)
- **Phase 2: Pipeline Core (Atoms P-04 - P-08)**: ワークフロー実行エンジン（`defpipeline`, `run-pipeline`）の実装。
- **Atom 17.4: src/term.lisp の刷新**: 不要になった旧式のプロセス管理コード（`proc.lisp` の遺産等）を削除し、CP プロトコルへの完全移行。

## 開発の指針
- **Warnings are Errors**: コード変更時は必ず `sbcl --load scripts/lint.lisp` を通すこと。
- **Atom Integrity**: 1つのAtomでテストが通らない場合は、関連するAtomを慎重に組み合わせて「常にグリーン」を保つこと。
