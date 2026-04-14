# Excalidraw Diagram Block

## Purpose

Markdown コードブロック（` ```excalidraw `）を使って Excalidraw 図を埋め込む機能。カーソルがブロック外にある場合は SVG プレビューを表示し、編集ボタンからフルスクリーンの Excalidraw エディタを起動できる。

## Requirements

### Requirement: Excalidraw コードブロックの SVG プレビュー表示

エディタは ` ```excalidraw ` フェンスコードブロックを検出し、カーソルがブロック外にある場合は Excalidraw scene JSON を SVG としてレンダリングした LivePreview ウィジェットを表示しなければならない（SHALL）。要素が存在しない場合は空のキャンバスを示すプレースホルダー表示を行う。

#### Scenario: 有効な Excalidraw scene JSON が入力されている場合のプレビュー

- **WHEN** ユーザーが ` ```excalidraw ` コードブロックの外にカーソルを置いている
- **THEN** コードブロック全体が非表示になり、代わりに Excalidraw の内容を SVG で描画したウィジェットが表示される

#### Scenario: コードブロックが空の場合のプレビュー

- **WHEN** ` ```excalidraw ` コードブロックの内容が空またはホワイトスペースのみ
- **THEN** 「図を追加するにはクリックしてください」などのプレースホルダーウィジェットが表示される

#### Scenario: カーソルがブロック内にある場合

- **WHEN** カーソルが ` ```excalidraw ` コードブロック内のいずれかの行にある
- **THEN** プレビューウィジェットは非表示になり、生の Markdown テキスト（コードブロック記法含む）が表示される

### Requirement: ホバーで編集ボタン表示

SVG プレビューウィジェットにマウスを重ねると編集ボタンが表示されなければならない（SHALL）。

#### Scenario: プレビューウィジェットへのホバー

- **WHEN** ユーザーが Excalidraw SVG プレビューウィジェット上にマウスカーソルを移動させる
- **THEN** ウィジェット上に「編集」ボタンが表示される

#### Scenario: プレビューウィジェットからマウスが離れた場合

- **WHEN** ユーザーがウィジェット上からマウスカーソルを移動させる
- **THEN** 編集ボタンが非表示になる

### Requirement: Excalidraw エディタのフルスクリーン表示

編集ボタンを押下すると、Excalidraw エディタがノートウィンドウ全体を覆うオーバーレイとして表示されなければならない（SHALL）。

#### Scenario: 編集ボタンの押下

- **WHEN** ユーザーが Excalidraw プレビューウィジェットの編集ボタンをクリックする
- **THEN** Excalidraw エディタが WebView 全体を覆うオーバーレイとして表示され、コードブロックの既存 JSON がロードされる

#### Scenario: 空のコードブロックからの編集開始

- **WHEN** コードブロックが空の状態で編集ボタンをクリックする
- **THEN** Excalidraw エディタが空の初期キャンバスとして表示される

### Requirement: 編集完了とコードブロック更新

Excalidraw エディタを閉じると、最新の scene JSON がコードブロック内容として保存されなければならない（SHALL）。

#### Scenario: 編集終了

- **WHEN** ユーザーが Excalidraw エディタのオーバーレイを閉じる（閉じるボタンまたは Escape キー）
- **THEN** オーバーレイが閉じ、コードブロック内の JSON が編集後の Excalidraw scene JSON に更新され、CodeMirror の `contentChanged` イベントが発火する

#### Scenario: 変更なしで編集終了

- **WHEN** ユーザーが何も変更せずにオーバーレイを閉じる
- **THEN** コードブロック内容は変更されず、ファイルへの不要な書き込みは発生しない
