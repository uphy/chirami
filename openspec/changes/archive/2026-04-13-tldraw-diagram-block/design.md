## Context

editor-web は CodeMirror 6 ベースの TypeScript アプリで、すでに Mermaid・画像・テーブルなどをプラグイン（`src/extensions/`）として実装している。Swift 側は WKWebView + `NoteWebViewBridge` でメッセージ交換しており、JS→Swift（`window.webkit.messageHandlers.chirami.postMessage`）と Swift→JS（`evaluateJavaScript`）の双方向通信がある。

tldraw は React ベースのダイアグラムライブラリ。コードブロック内に tldraw の `TLStore` スナップショット JSON を保存し、CodeMirror の LivePreview と同じ仕組みで SVG プレビューを差し込む。

## Goals / Non-Goals

**Goals:**
- ` ```tldraw ` コードブロックの LivePreview として SVG を描画
- ホバー時に編集ボタン、クリックでエディタオーバーレイ表示
- 編集完了でコードブロック JSON を更新

**Non-Goals:**
- tldraw 図のエクスポート（PNG/SVG ファイルとして保存）
- Obsidian での tldraw 表示（JSON がそのまま見える状態を許容）
- リアルタイムコラボレーション

## Decisions

### tldraw エディタの表示方法

**決定**: JS 側のフルスクリーン overlay div（同一 WKWebView 内）で実装する。

- **理由**: Swift 側に新たな WKWebView を追加するより、既存の editor-web バンドル内で完結させる方がシンプル。CodeMirror への Swift→JS メッセージングと同じ仕組みを流用できる。
- **代替案**: Swift 側で別 WKWebView をモーダル表示 → Swift/JS 間の状態同期が複雑になり却下。

### React 導入

**決定**: tldraw を使用するために React を editor-web に追加する。

- **理由**: tldraw は React コンポーネントとして提供されており、React なしでは使えない。SVG 描画のみ別途 headless で行う案も検討したが、tldraw の `@tldraw/tldraw` パッケージは React で完全統合されているため素直に追加する。
- **バンドルサイズ**: tldraw は大きい（数 MB）が、editor-web は WKWebView に組み込むローカルバンドルのためネットワーク遅延がなくロード時間の影響は軽微。

### SVG プレビューの生成

**決定**: tldraw の `TldrawImage` React コンポーネントを使ってスナップショット JSON から静的プレビューを描画する。

- `WidgetType.toDOM()` 内でプレビュー用 `<div>` を作成し、`createRoot().render(<TldrawImage snapshot={...} />)` でマウント。
- `WidgetType.destroy()` で React root を unmount。
- 当初は headless `<Tldraw>` + `editor.getSvg()` を検討していたが、`TldrawImage` が静的プレビュー用に設計されておりよりシンプルなため採用。

### Swift↔JS の通信

**決定**: 編集モード中の Swift 側対応は最小限にする。

- オーバーレイの開閉は完全に JS 側で制御。
- 編集終了時に `contentChanged` メッセージで更新後の Markdown テキスト全体を送信（既存フロー）。
- `overlayVisible` メッセージを追加し、オーバーレイ表示中は Swift 側でウィンドウ操作（クリックスルーなど）を抑制できるようにした。

## Risks / Trade-offs

- **バンドルサイズ肥大化** → React + tldraw で大幅増加。初回 WebView ロード時間が伸びる可能性。初回ロードは起動時のみでキャッシュが効くため許容範囲と判断。軽減策: コードスプリッティングで tldraw を遅延ロード。
- **空コードブロック問題** → 新規作成時は JSON が空。tldraw は空の初期状態から開始し、閉じると最小限の JSON を書き込む。
- **tldraw API の変更** → tldraw は活発に開発されており破壊的変更が多い。バージョンを固定し、アップデート時はテストを念入りに行う。
