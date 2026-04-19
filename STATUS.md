# Project Status: photo-ai-lisp

## 2026-04-19 状況認識

### 1. CI/品質管理 (Current Baseline)
- **厳密なLintの導入**: `scripts/lint.lisp` により、`asdf:load-system` 時に発生する全ての `WARNING`（スタイル警告、再定義、未使用変数等）をエラーとして扱う運用を開始。
- **クリーンなコードベース**: 重複していた `%json-escape` の削除、`spawn-child` の引数シグネチャの統一（全て `&key` へ）、テスト内の未使用変数の解消を完了。
- **GitHub Actions**: 高速（1分以内）かつ、警告のない「内容の伴ったグリーン」を維持。

### 2. 進捗状況 (Atom Landing)
- **Business UI (Atoms 01-07)**: 完了。
  - `/`, `/cases`, `/cases/:id` のルーティングとハンドラが配線済み。
  - 既存のカバレッジテスト維持のため、`home-page` には `/term` への隠しリンクを一時的に保持。
- **Pipeline (Atoms 01-03)**: 完了。
  - スキル登録（`register-skill`, `find-skill`, `unregister-skill`）が着陸。
  - `pipeline-01` と `03` はテストの依存関係により同時適用。

### 3. 次の課題 (Next Actions)
- **Pipeline Core (Atoms 04-08)**: ワークフロー実行エンジンの核心部（`defpipeline`, `run-pipeline`）の実装。
- **Windows固有ロジックの検証**: 現状CIはUbuntuだが、実機（Windows）での外部プロセス起動（Ghostty/PowerShell）の結合試験が必要。
- **Open Questionsの解消**: `REQUIREMENTS.md` 第7節にある設計判断（エージェントの分離ポリシー等）を要件へ昇格させる。

## 開発の指針
- **Warnings are Errors**: コード変更時は必ず `sbcl --load scripts/lint.lisp` を通すこと。
- **Atom Integrity**: 1つのAtomでテストが通らない場合は、関連するAtomを慎重に組み合わせて「常にグリーン」を保つこと。
