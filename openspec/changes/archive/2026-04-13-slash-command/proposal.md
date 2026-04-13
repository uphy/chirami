## Why

Markdownブロック要素（tldraw・mermaid・table など）を挿入するには現状テキスト手入力しかなく、コードフェンスの記法を知っていなければ使えない。行頭で `/` を入力するスラッシュコマンドを導入し、ブロック要素を素早く発見・挿入できるようにする。

## What Changes

- CodeMirror extension としてスラッシュコマンドシステムを新規実装
- `/` を行頭で入力するとコマンドピッカーが表示され、キーボードで選択・挿入できる
- 初期コマンド: `/tldraw`（挿入 + オーバーレイ open）、`/mermaid`（挿入 + カーソル配置）、`/table`（テンプレート挿入 + カーソル配置）
- スラッシュコマンド基盤は将来のコマンド追加に対応できる拡張可能な設計にする

## Capabilities

### New Capabilities

- `slash-command`: 行頭 `/` でコマンドピッカーを呼び出し、ブロック要素を挿入するエディタ機能

### Modified Capabilities

## Impact

- `editor-web/src/extensions/` に新規ファイル（`slashCommand.ts` など）を追加
- `editor-web/src/editor.ts` に extension を組み込み
- `editor-web/src/style.css` にコマンドピッカーのスタイルを追加
- `editor-web/src/extensions/tldraw.ts` の `openTldrawOverlay` を再利用
- 新規 npm 依存なし（純粋な CodeMirror + DOM 実装）
