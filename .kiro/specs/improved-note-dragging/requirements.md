# Requirements Document

## Introduction

Fusen の付箋ウィンドウは `isMovableByWindowBackground = true` が設定されているが、コンテンツ領域を占める MarkdownTextView (NSTextView) がマウスイベントを消費するため、実質的にタイトルバーからしかウィンドウを移動できない。タイトルバーは狭く、ドラッグ対象として掴みにくい。本仕様では、コンテンツ領域からもウィンドウをドラッグ移動できるようにし、操作性を向上させる。

## Requirements

### Requirement 1: 修飾キー付きドラッグによるウィンドウ移動

**Objective:** ユーザーとして、コンテンツ領域上でも修飾キーを押しながらドラッグすることでウィンドウを移動したい。テキスト編集操作と移動操作を明確に区別できるようにするため。

#### Acceptance Criteria

1. While 修飾キー (Option) が押されている状態で、When ユーザーがコンテンツ領域をドラッグした場合、the Fusen shall ウィンドウをドラッグに追従して移動させる
2. While 修飾キーが押されていない状態で、When ユーザーがコンテンツ領域をドラッグした場合、the Fusen shall 従来通りテキスト選択を実行する
3. When 修飾キー付きドラッグによるウィンドウ移動が完了した場合、the Fusen shall 移動後のウィンドウ位置を永続化する (既存の `windowDidMove` の挙動と同等)

### Requirement 2: ドラッグ中のカーソル表示

**Objective:** ユーザーとして、ウィンドウ移動モードに入ったことが視覚的に分かるようにしたい。意図した操作が行われていることを確認できるようにするため。

#### Acceptance Criteria

1. While 修飾キーが押されコンテンツ領域上にカーソルがある状態で、the Fusen shall カーソルを移動用カーソル (open hand / closed hand) に変更する
2. When 修飾キー付きドラッグが開始された場合、the Fusen shall カーソルを closed hand カーソルに変更する
3. When 修飾キーが離された場合、the Fusen shall カーソルを通常のテキスト編集カーソルに戻す

### Requirement 3: 既存機能との互換性

**Objective:** ユーザーとして、ドラッグ改善によって既存の操作が壊れないようにしたい。テキスト編集、チェックボックス操作、リンククリックなどの機能を引き続き利用できるようにするため。

#### Acceptance Criteria

1. When ユーザーが修飾キーなしでテキストをクリックした場合、the Fusen shall 従来通りカーソルを配置しテキスト編集を開始する
2. When ユーザーが修飾キーなしでチェックボックスをクリックした場合、the Fusen shall 従来通りチェックボックスの状態を切り替える
3. When ユーザーが修飾キーなしでリンクをクリックした場合、the Fusen shall 従来通りリンクをブラウザで開く
4. The Fusen shall タイトルバーからの通常ドラッグ移動を引き続きサポートする
5. While ウィンドウの position モードが `.cursor` の場合、When 修飾キー付きドラッグで移動が完了した場合、the Fusen shall `.cursor` モードの挙動に従いウィンドウ位置を永続化しない
