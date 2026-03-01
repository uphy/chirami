## Why

`chirami display` でCLIからMarkdownコンテンツを表示できるようになったが、現状は一方通行の「表示のみ」に留まる。AIエージェントのhookやシェルスクリプトでは、表示した内容に対してユーザーの判断（承認/却下）やテキスト入力、選択肢からの選択を受け取りたいユースケースがある。

付箋UIでフィードバックを受け取れれば、フローを中断せずにhuman-in-the-loopを実現できる。別のアプリに切り替えてダイアログを操作する必要がなく、Product Visionの「without breaking your flow」に合致する。

## What Changes

- `chirami confirm` サブコマンドを新規追加する — Markdown本文を表示し、下部にOK/Cancelボタンを配置。OKでexit 0、Cancelでexit 1を返す
- `chirami input` サブコマンドを新規追加する — Markdown本文を表示し、下部にテキスト入力欄とSubmitボタンを配置。入力テキストをstdoutに出力してexit 0を返す
- `chirami select` サブコマンドを新規追加する — Markdown本文を表示し、下部に選択肢ボタンを配置。選択結果をstdoutに出力してexit 0を返す
- FIFOプロトコルを拡張し、`CLOSED` に加えて `CONFIRMED`、`CANCELLED`、`RESULT:<value>` メッセージを追加する
- 既存の `display` サブコマンドには変更なし

## Capabilities

### New Capabilities

- `cli-confirm`: CLIからMarkdownコンテンツを表示し、ユーザーのOK/Cancel判断をexit codeで返す
- `cli-input`: CLIからMarkdownコンテンツを表示し、ユーザーのテキスト入力をstdoutに返す
- `cli-select`: CLIからMarkdownコンテンツを表示し、ユーザーの選択肢選択をstdoutに返す

### Modified Capabilities

- `cli-display`: FIFOプロトコルの拡張（`CLOSED` に加えて新メッセージ追加）。ただしcli-displayの外部仕様（CLI引数、exit code）は変更なし

## Impact

- 新規: `cmd/chirami/confirm.go`, `input.go`, `select.go`（Go CLIサブコマンド）
- 新規: `Chirami/Display/` にフィードバックUI用のSwiftUIコンポーネント（ボタンバー、テキスト入力欄）
- 変更: `Chirami/Display/DisplayWindowManager.swift` — 新しいURIホスト（`confirm`, `input`, `select`）のハンドリング追加
- 変更: `Chirami/Display/DisplayPanel.swift` — FIFOプロトコルの拡張（結果メッセージの送信）
- 変更: `cmd/chirami/main.go` — 新サブコマンドの登録
- 変更: `cmd/chirami/internal/fifo.go` — 新メッセージの読み取りロジック追加
