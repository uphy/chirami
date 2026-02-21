# Fusen バグ修正計画

## Context

Fusen アプリで3つの問題が報告された:

1. Markdown を入力してもスタイルが反映されない
2. ウィンドウの色が選択しても変わらない
3. タイトルをネイティブのウィンドウタイトルとして表示したい

## 修正1: Markdown スタイリング

**原因**: 3つの問題の複合

- **再帰ループ**: `applyStyling()` が `setSelectedRange()` を呼び、それが `textViewDidChangeSelection` を発火、再び `applyStyling()` が呼ばれる。二重スタイリングやフリッカーが発生
- **nsRange の文字単位が不正**: `MarkdownStyler.nsRange()` が `String.count`（書記素クラスタ数）で計算しているが、NSRange は UTF-16 単位。swift-markdown の column は UTF-8 バイトオフセット。非ASCII文字で範囲がずれてスタイルが適用されない
- **二重パース**: `BlockTracker` と `MarkdownStyler` がそれぞれ独立に `Document(parsing:)` を呼ぶ

**修正内容**:

`Fusen/Views/LivePreviewEditor.swift`:
- Coordinator に `isApplyingStyling` フラグを追加。`textViewDidChangeSelection` と `applyStyling` の冒頭でガード
- `blockTracker` プロパティを削除。`styler.style(text, cursorLocation:)` に一本化
- `applyStyling` の API 呼び出しを新シグネチャに変更

`Fusen/Editor/MarkdownStyler.swift`:
- `nsRange(for:in:)` を全面書き換え: UTF-8 バイト→`String.Index`→`NSRange(_:in:)` で正しく UTF-16 変換
- `style(_:cursorLocation:)` 新メソッドを追加。内部でカーソルブロック検出 + スタイル適用を一括処理（Document パース1回）
- 旧 `style(_:cursorBlockRange:)` を削除

`Fusen/Editor/BlockTracker.swift`:
- ファイル削除（ロジックは MarkdownStyler に統合済み）

## 修正2: 色変更が反映されない

**原因**: `Note` は struct（値型）で、`NoteWindowController` と `NoteContentView` が `let note: Note` として初期化時の値を保持。`NoteStore.updateColor()` が新しい `Note` 配列を生成しても、既存ウィンドウの `note` は古いまま。`NSPanel.backgroundColor` も `init` で1度だけ設定。

**修正内容**:

`Fusen/Models/Note.swift`:
- `Equatable` を全フィールド比較に変更（`id` だけでなく `color`, `title`, `path` も比較）

`Fusen/Views/NoteWindow.swift`:

NoteWindowController:
- `noteStore.$notes` の Combine subscription を追加
- `applyNoteUpdate(_:)` メソッドで `panel.backgroundColor` と `panel.title` を更新

NoteContentView:
- `let note: Note` → `let noteId: String` に変更
- `@ObservedObject private var noteStore = NoteStore.shared` を追加
- `noteStore.notes` から `noteId` で現在の `Note` を取得する computed property を追加
- body 内の `note.color` 参照が自動的に最新値を使うようになる

ColorPickerView:
- `note.id` だけ使うので変更不要（`NoteStore.shared.updateColor` は `note.id` で検索する）

## 修正3: ネイティブウィンドウタイトル

**原因**: `panel.titleVisibility = .hidden` でタイトル非表示、`.fullSizeContentView` でコンテンツがタイトルバー下に拡張、カスタム HStack でタイトルを表示している。

**修正内容**:

`Fusen/Views/NoteWindow.swift`:

NoteWindowController.init:
- `titleVisibility = .visible` に変更
- `titlebarAppearsTransparent = true` は維持（ノート色がタイトルバーに透ける）
- styleMask から `.fullSizeContentView` を削除

NoteContentView:
- カスタムタイトルバー（HStack + Divider、行185-209）を削除
- 色変更は右クリックコンテキストメニューに移動: `.contextMenu { Button("Change Color...") { showColorPicker = true } }`

## 検証方法

```bash
swift build -c release 2>&1 | tail -3
# バイナリ直接実行
.build/release/Fusen &
```

手動確認:
- `# 見出し` `**太字**` `*斜体*` を入力 → カーソル外のブロックでスタイルが反映される
- 日本語混じりの Markdown でもスタイルが正しい位置に適用される
- 色パレットから色を選択 → ウィンドウ背景色が即座に変わる
- ウィンドウのネイティブタイトルバーにノートタイトルが表示される
- 右クリックで色変更メニューが表示される
