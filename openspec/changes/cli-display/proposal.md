## Why

Chirami はGUIアプリとして優れたMarkdown閲覧体験を提供しているが、CLIやスクリプトから動的にコンテンツを表示する手段がない。AIエージェントのhookやシェルスクリプトから「一時的なMarkdownウィンドウを出す」ユースケースへの対応が必要になった。

## What Changes

- `chirami display` サブコマンドを新規追加する（**URI scheme + Go CLI方式**で実装）
- 引数・`--file` オプション・stdinの3通りでMarkdownコンテンツを受け取り、フローティングウィンドウで表示する
- デフォルトはノンブロッキング（ウィンドウを開いてすぐにexit 0）。`--wait` フラグ時のみウィンドウが閉じるまでブロックする
- 設定ファイル・状態ファイルへの読み書きは一切行わない（使い捨て設計）
- Chirami.appが未起動の場合は自動起動して表示する

## Capabilities

### New Capabilities

- `cli-display`: CLIからMarkdownコンテンツを受け取りフローティングウィンドウで表示する。引数・ファイル・stdinに対応し、`--wait` フラグ時はウィンドウを閉じるとプロセスが終了する

### Modified Capabilities

## Impact

- 新規: `cmd/chirami/` ディレクトリ（Go CLIバイナリ）— `main.go`, `display.go`, `internal/uri.go`, `internal/fifo.go`
- 新規: `Chirami/Display/` ディレクトリ — `DisplayPanel.swift`, `DisplayContentView.swift`, `DisplayWindowManager.swift`
- 変更: `Chirami.app` に `chirami://display` URI schemeハンドラを追加（`Info.plist` + `onOpenURL`）
- 変更: `mise.toml` のビルドタスクに Go CLIのビルドを追加
- 配布: `chirami`（Go binary）を `Chirami.app/Contents/MacOS/` に同梱する
