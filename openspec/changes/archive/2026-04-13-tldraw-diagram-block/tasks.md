## 1. 依存ライブラリの追加

- [x] 1.1 `editor-web/` に `tldraw` と `react`・`react-dom` を追加（npm install）
- [x] 1.2 `vite.config.ts`（またはビルド設定）に React JSX サポートを追加
- [x] 1.3 tldraw を動的インポート（コードスプリッティング）でバンドルサイズを分離

## 2. SVG プレビューウィジェットの実装

- [x] 2.1 `src/extensions/tldraw.ts` を新規作成（mermaid.ts を参考に骨格を作る）
- [x] 2.2 CodeMirror `ViewPlugin` で ` ```tldraw ` ブロックを検出しデコレーションを適用
- [x] 2.3 `TldrawPreviewWidget extends WidgetType` を実装し、`toDOM()` で SVG レンダリング用コンテナを返す
- [x] 2.4 tldraw の `getSvg()` / `exportAs` API を使ってスナップショット JSON から SVG を生成し、コンテナに挿入
- [x] 2.5 JSON が空の場合のプレースホルダー表示を実装

## 3. ホバーで編集ボタン表示

- [x] 3.1 `TldrawPreviewWidget.toDOM()` でウィジェット DOM に mouseover/mouseout イベントリスナーを追加
- [x] 3.2 編集ボタン要素を作成し、ホバー中のみ表示する CSS クラス切り替えを実装
- [x] 3.3 プレースホルダー（空コードブロック）も同様にクリックで編集開始できるようにする

## 4. tldraw エディタオーバーレイの実装

- [x] 4.1 `src/tldraw-overlay.tsx` を新規作成（React コンポーネント: `<TldrawOverlay>`）
- [x] 4.2 `<TldrawOverlay>` が `onClose(snapshot: string)` コールバックを受け取り、閉じるボタン / Escape で呼び出す設計にする
- [x] 4.3 overlay が WebView 全体を覆う `position: fixed; inset: 0; z-index: 9999;` スタイルを適用
- [x] 4.4 `<Tldraw>` コンポーネントに既存 JSON をロード（`initialState` / `loadSnapshot`）して表示
- [x] 4.5 `document.body` に overlay root div を動的マウント・アンマウントする管理関数を実装

## 5. 編集完了とコードブロック更新

- [x] 5.1 overlay close 時に `editor.store.getSnapshot()` で JSON を取得
- [x] 5.2 変更がない場合（初期 JSON と同一）はコードブロック更新をスキップ
- [x] 5.3 CodeMirror トランザクションでコードブロック内の JSON 文字列を新しいスナップショット JSON で置換
- [x] 5.4 `contentChanged` メッセージが発火し、Swift 側がファイルを保存することを確認

## 6. エディタへの組み込み

- [x] 6.1 `src/extensions/tldraw.ts` の `tldrawExtension` を `src/editor.ts`（または `main.ts`）に追加
- [x] 6.2 スタイル（`.cm-tldraw-container`、ホバーボタン、overlay）を `src/style.css` に追加

## 7. ビルドと動作確認

- [x] 7.1 `mise run build:editor` でビルドが通ることを確認
- [ ] 7.2 空の tldraw ブロック → 編集 → 保存 → SVG プレビュー表示の一連フローを動作確認
- [ ] 7.3 既存の tldraw JSON を持つブロックの編集・更新を確認
- [ ] 7.4 カーソルをブロック内に置いたときに生テキストが表示されることを確認
