## 1. Fold State Model

- [x] 1.1 `FoldingState` 構造体を定義する（ノートパスをキーに、折りたたまれた開始行番号のセットを保持）
- [x] 1.2 `AppState` に `foldingStates: [String: FoldingState]` プロパティを追加し、state.yaml への読み書きを実装する

## 2. Foldable Block Detection

- [x] 2.1 `MarkdownStyler` に「折りたたみ可能なブロックの開始行番号とブロック種別を列挙する」メソッドを追加する（見出し H1〜H6、トップレベルリスト）
- [x] 2.2 折りたたまれたブロックの子ノードをスタイリング時にスキップするロジックを `MarkdownStyler` に実装する

## 3. Fold Indicator Rendering

- [x] 3.1 `BulletLayoutManager` の `drawBackground` で、折りたたみ済みブロックの最終表示行左マージンに `>` インジケーターを描画する処理を追加する
- [x] 3.2 インジケーターの色・フォント・位置を既存のカスタム描画スタイルに合わせて調整する

## 4. Toggle Button Overlay

- [x] 4.1 `LivePreviewEditor` (NSTextView サブクラスまたは Coordinator) に、現在カーソルがあるフォールド可能ブロックの開始行位置を計算するロジックを追加する
- [x] 4.2 オーバーレイ `NSButton`（シェブロンアイコン）を生成・再利用するヘルパーを実装する
- [x] 4.3 カーソル移動イベント（`didChangeSelection`）でトグルボタンの表示・位置・アイコン方向を更新する
- [x] 4.4 トグルボタンのクリック時に `FoldingState` を更新し、`MarkdownStyler` を再実行してビューを再描画する

## 5. State Persistence Integration

- [x] 5.1 ノートを開くとき、`AppState` から該当ノートの `FoldingState` を読み込み、`MarkdownStyler` に渡す
- [x] 5.2 折りたたみ状態が変更されるたびに `AppState` を更新・保存する
- [x] 5.3 ファイル外部変更検知後に折りたたみ状態を再検証し、存在しない行番号の状態を破棄する
