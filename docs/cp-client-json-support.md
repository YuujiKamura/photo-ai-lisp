# CP Client JSON Response Support

## 変更サマリ
- CP プロトコルのパースロジックを更新し、JSON 形式のレスポンスを plist としてパースできるようにしました。
- `shasht` ライブラリを依存関係に追加しました。
- `pipeline-cp` の `invoke-via-cp` を、JSON モードではセッションステータスが `idle` になるのを待機するロジックに変更しました。
- 既存のパイプ区切り形式（legacy pipe format）との後方互換性を維持しました。

## 新 API (plist 形状の詳細、キー一覧)
`cp-parse-response` が JSON を受け取ると以下の plist を返します：
- `:cmd` - コマンド名 ("INPUT", "SHOW", "STATE" 等)
- `:ok` - 成功フラグ (t または nil)
- `:error` - エラーメッセージ
- `:data` - データ本体 (base64 エンコードされた文字列等)
- `:status` - ステータス ("active", "idle" 等)
- `:mode` - モード ("buffer" 等)
- `:message` - 付随メッセージ

## legacy pipe 形式との互換性
- 入力が `{` で始まらない場合は、従来通り `|` で分割された文字列のリストを返します。
- `invoke-via-cp` は、最初のレスポンスが JSON でない場合、従来の `DONE|` マーカーを `TAIL` (SHOW) で監視するループに自動的に切り替えます。

## pipeline-cp の completion 判定ロジック変更
- **JSON モード**: `STATE` コマンドを定期的にポーリングし、`:ok t` かつ `:status "idle"` になった時点で完了とみなします。タイムアウトは 50 秒（1秒間隔で 50 回）です。
- **Legacy モード**: 従来通り `TAIL` (SHOW) コマンドで最後の 10 行を取得し、`DONE|<skill-name>|` マーカーを検索します。タイムアウトは 5 秒（0.1秒間隔で 50 回）です。
