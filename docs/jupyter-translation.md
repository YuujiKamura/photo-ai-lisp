# Jupyter Translation — 外部完成品からの設計輸入 (2026-04-21)

## 目的
photo-ai-lisp の Tier 1-3 は「browser + hub + agent + terminal iframe」の設計を scratch で実装してきた。本書は **Jupyter messaging spec + Jupyter AI + Agent Client Protocol (ACP) + MCP** から設計思想を翻訳・移植し、scratch 部分を標準パターンに差し替える方針を定義する。

**重要前提** (skill `borrow-external-reference` / memory `feedback_no_experiment_framing` 参照):
- photo-ai-lisp は production 作業 (cost-bearing)、実験ではない
- Python エコシステム依存は避ける (ユーザー方針: Python クソコード汚染疑惑) → **Python コードを輸入せず、設計思想を Lisp に翻訳する**
- 翻訳対象は OSS (Jupyter は BSD-3、ACP/MCP も open spec)

## 参照先 (local clone at `C:/Users/yuuji/ref/`)
- `jupyter_client/docs/messaging.rst` (2078 行) — 10 年実戦の messaging spec
- `jupyter_server/` — WS + session routing
- `jupyter-ai/` — LLM agent 統合、ACP/MCP host 実装
- https://agentclientprotocol.com — Agent Client Protocol spec
- https://modelcontextprotocol.io — Model Context Protocol spec

## 現状 (photo-ai-lisp の bespoke CP) vs Jupyter 標準

### 1. メッセージエンベロープ
**Jupyter (5-part)**:
```json
{
  "header":        {"msg_id": UUID, "session": UUID, "username": str,
                    "date": ISO8601, "msg_type": str, "version": "5.0"},
  "parent_header": {"msg_id": ...},  // 返信時は元 request の header を写す
  "metadata":      {},
  "content":       {...},             // msg_type ごとのスキーマ
  "buffers":       []                 // binary blob list (画像/音声)
}
```
**photo-ai-lisp (現状)**:
```json
{"cmd":"INPUT","from":"photo-ai-lisp","msg":"<base64>","session":"<name>"}
```

**ギャップ**:
- ❌ `msg_id` 無し → 同種 request が複数飛ぶと reply 対応付け不能
- ❌ `parent_header` 無し → **非同期 reply を request に紐付けられない**。これは PR #24 で Gemini が指摘した「send-cp-command が timeout しない」bug の根本原因の 1 つ。parent_header があれば pending-request table でルーティング可能
- ❌ `version` 無し → protocol 進化時の互換性破綻
- ❌ session 概念が string 名だけ、UUID じゃない → kernel restart 検出不能 (Jupyter は session UUID 変更で restart を frontend に通知)

**翻訳 action**: `src/cp-protocol.lisp` の `make-cp-*` を 5-part envelope に拡張。最小でも `msg_id` (UUID) + `parent_header` を追加。

### 2. チャネル分離
**Jupyter (3 channel)**:
- **Shell** (req/rep): execute_request ↔ execute_reply。1-to-1 対応
- **IOPub** (broadcast): stdout/stderr/display_data/status を全 frontend に push。1-to-many
- **Stdin** (reverse req): kernel → frontend の input 要求 (対話的 `input()`)

**photo-ai-lisp (現状)**: 単一 WS に全種類混在。

**ギャップ**:
- ❌ agent 出力 (iframe の terminal stream) と control reply (STATE/LIST の JSON 応答) が同じ channel で競合
- ❌ agent が long-running 中に status (busy/idle) を別 channel で broadcast できない
- ❌ 複数 frontend (browser + CLI 監視) が同じ agent を watch する multi-subscriber パターンが組めない

**翻訳 action**: 1 WS 内で **msg_type で論理 channel を切る**。`kernel_status` (busy/idle)、`stream` (stdout/stderr)、`execute_reply` を msg_type で分けて frontend 側で dispatch。

### 3. 必須メッセージタイプ
**Jupyter 必須**: `execute_request` / `execute_reply` / `kernel_info_request` / `kernel_info_reply` / `status` (busy|idle)。

**photo-ai-lisp 現状**: INPUT / SHOW / STATE / LIST。

| photo-ai-lisp | Jupyter 相当 | gap / 改善点 |
|---------------|-------------|--------------|
| INPUT | execute_request | `msg_id` + `silent` + `stop_on_error` 追加。reply を execute_reply 形式で返す |
| SHOW | stream (IOPub) | pull じゃなく push、broadcast channel |
| STATE | status (IOPub broadcast) | busy/idle を状態変化で自動 broadcast、pull で問い合わせじゃない |
| LIST | kernel_info_request (per session) + kernel_manager の list_running | agent capability discovery を含める (model name、tools) |
| (なし) | kernel_info_reply | 新設。agent の model/capabilities を宣言 |
| (なし) | execution_count | 監査 log の相関 key として有用 |

### 4. busy/idle semantics (最重要)
Jupyter の IOPub で kernel は **実行開始時に `status: busy`、完了時に `status: idle`** を broadcast。frontend はこれを見て progress indicator を出す。photo-ai-lisp では agent が長時間 thinking 中かどうかを frontend が知る手段がない。

**翻訳 action**: `src/cp-ui-bridge.lisp` の INPUT handler で:
1. agent session に送信前: `{"msg_type":"status","content":{"execution_state":"busy"}}` を broadcast
2. agent の最後出力を受信後: `{"msg_type":"status","content":{"execution_state":"idle"}}` を broadcast
   (または idle detection heuristic: prompt return pattern match)

### 5. ACP (Agent Client Protocol) ー 別次元の発見
https://agentclientprotocol.com = **AI agent 接続の業界標準 open protocol**。Jupyter AI がこれで Claude/Codex/Gemini/Goose/Kiro/Mistral/OpenCode を統合している。

**意味**:
- photo-ai-lisp の CP (bespoke) を ACP compliant にすれば、**deckpilot + claude subprocess の独自実装を捨てて ACP standard agent をぶら下げられる**
- 他 agent も同 protocol で swap 可能 (Tier 3 dogfood で「claude vs codex vs gemini」の比較も可能)

**翻訳 action**: 仕様書を読んで CP を ACP compatible に寄せられるか調査する (今すぐ pivot はしない、Tier 1-2 完走後の方針決定材料)。

### 6. MCP (Model Context Protocol) ー tool 統合
https://modelcontextprotocol.io = tool access 標準。既に Claude Code が native対応。photo-ai-lisp の Tier 3 real-task (photo-import pipeline 駆動) = `photo-ai-go` CLI 実行は、**MCP server として photo-ai-go を wrap** すれば claude が直接 tool 呼出しで使える。hub / deckpilot の中間層を挟まずに済む可能性。

**翻訳 action**: `photo-ai-go` を MCP server 化する小さい atom を Tier 2 / Tier 3 の間に挿入検討。

## 優先順位 (shipping までの最短経路)

1. **P0 — parent_header 追加** (1-2 hour): CP envelope に msg_id + parent_header。pending-request table を hub に足す。PR #24 の timeout 問題が根本解決
2. **P0 — status (busy/idle) broadcast** (1 hour): INPUT ハンドラで execution_state を broadcast、frontend でも表示
3. **P1 — msg_type で channel 分離** (2 hour): 1 WS 内 msg_type dispatch、iframe が stream を直接受ける
4. **P1 — kernel_info equivalent** (1 hour): LIST に agent capability (model, tools) を含める
5. **P2 — ACP compatibility 調査** (4 hour研究): 仕様を読み、現 CP の gap を documented
6. **P2 — photo-ai-go を MCP server 化** (独立 atom、Tier 3 前に): Tier 3 real task の実装オプションが広がる

## やらない判断
- **Python コード輸入**: やらない。ユーザー方針。Jupyter の Python 実装は設計の参照のみ
- **ZMQ wire protocol**: やらない。現 WS で十分
- **HMAC signature**: やらない。localhost only で不要
- **IPython execution_count / In[N]/Out[N]**: やらない。notebook UX は Tier 2 scope 外

## 次アクション (主人格)
1. 上記 P0 2 件を BACKLOG.md に atom として追加 (feat/proto-v2 branch)
2. それぞれ Agent tool (Senior Developer, Sonnet) で実装 delegate、主人格 (Opus) は spec + verify
3. P2 ACP 仕様調査は Tier 1-2 land 後に改めて判断
