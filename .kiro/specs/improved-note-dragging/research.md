# Research & Design Decisions

## Summary

- **Feature**: `improved-note-dragging`
- **Discovery Scope**: Extension
- **Key Findings**:
  - `isMovableByWindowBackground = true` は設定済みだが、MarkdownTextView (NSTextView) が `mouseDown` を消費するため、コンテンツ領域からのドラッグが機能しない
  - AppKit の `NSWindow.performDrag(with:)` を使えば、任意のマウスイベントからプログラム的にウィンドウドラッグを開始できる
  - `flagsChanged(with:)` で修飾キーの押下/解放をリアルタイムに検知し、カーソルを動的に変更できる

## Research Log

### NSWindow.performDrag(with:) によるプログラム的ウィンドウ移動

- **Context**: NSTextView がマウスイベントを消費する中で、ウィンドウ移動を実現する方法の調査
- **Sources Consulted**: Apple Developer Documentation (NSWindow)
- **Findings**:
  - `performDrag(with: NSEvent)` は NSWindow のメソッドで、mouseDown イベントを渡すことでウィンドウドラッグを開始する
  - ドラッグ中のマウス追従・位置更新は AppKit が自動で処理する
  - ドラッグ完了後に `windowDidMove` デリゲートが呼ばれるため、既存の位置永続化ロジックがそのまま動作する
- **Implications**: MarkdownTextView の `mouseDown` で Option キーを検出した場合に `performDrag` を呼ぶだけで実現可能。カスタムのマウストラッキングは不要

### NSCursor による移動モードの視覚フィードバック

- **Context**: ユーザーに移動モードを視覚的に伝える手段の調査
- **Sources Consulted**: Apple Developer Documentation (NSCursor)
- **Findings**:
  - `NSCursor.openHand` — 移動可能状態を示す (Option 押下中のホバー)
  - `NSCursor.closedHand` — ドラッグ中を示す
  - `NSCursor.push()` / `NSCursor.pop()` — スタックベースのカーソル管理
  - `flagsChanged(with:)` は NSResponder のメソッドで、修飾キーの押下/解放時に呼ばれる
- **Implications**: `flagsChanged` と `mouseMoved` の組み合わせでカーソル変更を実装。`performDrag` がマウスイベントを引き継ぐため、ドラッグ中の closed hand は `performDrag` 呼び出し前に設定する

### 既存 MarkdownTextView のイベントフロー分析

- **Context**: 既存のマウスイベント処理との衝突リスクの評価
- **Findings**:
  - `mouseDown`: チェックボックスクリック → リンククリック → `super.mouseDown` (テキスト選択) の優先順で処理
  - `mouseMoved`: チェックボックス/リンク上は pointing hand、それ以外は super (I-beam)
  - Option キーは現在どのマウスイベントでも使用されていない
- **Implications**: Option キーのチェックを `mouseDown` の最優先に追加すれば、既存のチェックボックス/リンク/テキスト選択に干渉しない

## Design Decisions

### Decision: Option キーによるドラッグトリガー

- **Context**: テキスト編集とウィンドウ移動を区別する修飾キーの選択
- **Alternatives Considered**:
  1. Option (⌥) キー — macOS の標準的な「代替操作」修飾キー
  2. Control (⌃) キー — 右クリック/コンテキストメニューと競合する可能性
  3. Command (⌘) キー — テキスト編集ショートカット (Cmd+C, Cmd+V 等) と競合
- **Selected Approach**: Option (⌥) キー
- **Rationale**: macOS 上で Option は「代替動作」を示す標準的な修飾キーであり、テキスト編集のキーボードショートカットと競合しない。Finder でもOption+ドラッグで「コピー」という代替操作に使われる慣例がある
- **Trade-offs**: Option+ドラッグでの特殊文字入力が使えなくなるが、MarkdownTextView では特殊文字入力の需要は低い
- **Follow-up**: 実際のユーザーテストで操作感を確認

### Decision: performDrag ベースの実装

- **Context**: ウィンドウ移動をカスタム実装するかAppKit APIを使うか
- **Alternatives Considered**:
  1. `NSWindow.performDrag(with:)` — AppKit ネイティブ
  2. カスタム mouseDragged/mouseUp トラッキング — 手動でウィンドウ位置を更新
- **Selected Approach**: `performDrag(with:)`
- **Rationale**: AppKit がドラッグ追従・画面境界・マルチディスプレイを自動処理し、`windowDidMove` デリゲートも正常に呼ばれるため、既存の位置永続化ロジックとの統合が自然
- **Trade-offs**: ドラッグ中のカーソル制御が AppKit 側に移るため、closed hand カーソルの表示は performDrag 呼び出し前に設定する必要がある

## Risks & Mitigations

- **Option+ドラッグでの特殊文字入力不可** — MarkdownTextView での特殊文字入力需要は低いため許容。必要なら設定で修飾キーを変更可能にする (将来拡張)
- **performDrag のカーソル制御** — performDrag がイベントループを占有し、ドラッグ中の flagsChanged 配信タイミングが不確定。push/pop のネストではなく、performDrag 前後で明示的にリセットし、完了後に `modifierFlags` を再評価して整合性を保証する

## References

- [NSWindow.performDrag(with:)](https://developer.apple.com/documentation/appkit/nswindow/performdrag(with:)) — プログラム的ウィンドウドラッグ開始
- [NSCursor](https://developer.apple.com/documentation/appkit/nscursor) — カーソル種別と push/pop API
- [NSResponder.flagsChanged(with:)](https://developer.apple.com/documentation/appkit/nsresponder/flagschanged(with:)) — 修飾キー変更イベント
