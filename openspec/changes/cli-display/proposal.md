## Why

Chirami はGUIアプリとして優れたMarkdown閲覧体験を提供しているが、CLIやスクリプトから動的にコンテンツを表示する手段がない。AIエージェントのhookやシェルスクリプトから「一時的なMarkdownウィンドウを出す」ユースケースへの対応が必要になった。

## What Changes

- `chirami display` サブコマンドを新規追加する（新しいビルドターゲット `ChiramiDisplay` として実装）
- 引数・`--file` オプション・stdinの3通りでMarkdownコンテンツを受け取り、フローティングウィンドウで表示する
- プロセスはウィンドウが閉じるまでブロックし、exit code 0で終了する
- 設定ファイル・状態ファイルへの読み書きは一切行わない（使い捨て設計）

## Capabilities

### New Capabilities

- `cli-display`: CLIからMarkdownコンテンツを受け取りフローティングウィンドウで表示する。引数・ファイル・stdinに対応し、ウィンドウを閉じるとプロセスが終了する

### Modified Capabilities

## Impact

- `project.yml` に `ChiramiDisplay` ターゲットを追加する
- `Chirami/Editor/` ソースを `ChiramiDisplay` ターゲットと共有する
- 新規ファイル: `ChiramiDisplay/` ディレクトリ（main.swift, DisplayWindowController.swift 等）
- `mise.toml` にビルドタスクの更新が必要な場合がある
- 配布: `Chirami.app/Contents/MacOS/chirami-display` としてバンドルする（または独立バイナリ）
