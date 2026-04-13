## Why

作業中にビジュアルで考えをまとめたい、スクリーンシェア中にホワイトボード代わりに使いたいというニーズがある。Chirami の「float what you need」というビジョンを自然に拡張し、図や図解もフローティングノートの中で完結させる。

## What Changes

- ` ```tldraw ` コードブロックをサポート：JSON データを内部に保存
- プレビュー表示時は tldraw の SVG エクスポートで描画
- ブロックをホバーすると編集ボタンを表示
- 編集ボタン押下でノートウィンドウ全体に tldraw エディタを展開
- 編集完了（閉じる）で JSON を更新してプレビューに戻る
- Obsidian で開いたときは JSON がそのまま表示される（許容）

## Capabilities

### New Capabilities

- `tldraw-diagram-block`: Markdown の ` ```tldraw ` コードブロックで tldraw 図を埋め込み・編集できる機能

### Modified Capabilities

（なし）

## Impact

- `editor-web/` — tldraw ライブラリの追加、コードブロックレンダラの拡張
- `Chirami/` — WebView ↔ Swift メッセージングで編集モード切替の制御
- 依存追加: tldraw（npm パッケージ）
