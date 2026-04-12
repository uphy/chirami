# Phase 5: 基本インタラクション

## 目的

キーボードショートカット、チェックボックス widget、カーソル・スクロール位置の永続化を実装し、日常的な編集操作を現行の NSTextView 版と同等に揃える。

## 前提

- Phase 4 までの Live Preview が動作していること
- クラッシュせずに Markdown 編集ができること

## スコープ

### 含む

- CodeMirror キーマップ追加（`@codemirror/commands` の history / defaultKeymap / historyKeymap）
- 検索機能（`@codemirror/search`）
- カスタムキーマップ
  - Cmd+B / Cmd+I: 選択範囲を `**` / `*` で囲む
  - Cmd+L: カーソル行のチェックボックストグル
  - Cmd+F: 検索（@codemirror/search 標準）
  - Cmd++ / Cmd+-: フォントサイズ変更（Swift に通知）
  - Cmd+Enter: リンク open（Swift に通知）
- チェックボックス widget（`[ ]` / `[x]` をクリック可能なチェックボックスに置換）
- カーソル位置永続化（`cursorChanged` メッセージ → `state.yaml`）
- スクロール位置永続化（`scrollChanged` メッセージ → `state.yaml`）
- フォーカス要求 API（Swift → JS: `focus()`）

### 含まない

- 画像 widget・リサイズ（Phase 6）
- 折りたたみ（Phase 6）
- Smart Paste（Phase 6）
- テーブルのセル移動（スコープ外）

## 使用する CodeMirror パッケージ（追加分）

| パッケージ | 用途 |
|-----------|------|
| @codemirror/commands | 標準キーマップ、undo/redo |
| @codemirror/search | Cmd+F 検索機能 |

## タスク一覧

### JS 側

- [ ] `@codemirror/commands` `@codemirror/search` を追加
- [ ] `editor.ts` に history / keymap / search 拡張を追加
- [ ] `editor-web/src/extensions/keymap.ts` 作成（カスタムコマンド）
- [ ] `editor-web/src/extensions/checkbox.ts` 作成（WidgetType）
- [ ] Cmd+B / Cmd+I のマークダウン装飾コマンド
- [ ] Cmd+L のタスクトグルコマンド
- [ ] Cmd++ / Cmd+- のフォントサイズ変更 → Swift 通知
- [ ] Cmd+Enter のリンク open → Swift 通知
- [ ] チェックボックスクリックハンドラ
- [ ] カーソル変更通知（debounce 1000ms）
- [ ] スクロール変更通知（debounce 1000ms）
- [ ] `focus()` API の実装

### Swift 側

- [ ] `NoteWebViewBridge.swift` に `cursorChanged` / `scrollChanged` / `openLink` / `fontSizeChange` ハンドラ追加
- [ ] `NoteWebView.swift` に `setCursorPosition(offset:)` / `setScrollPosition(offset:)` / `focus()` 追加
- [ ] `NoteContentModel` / `state.yaml` との接続
- [ ] `AppState.shared` にカーソル・スクロール位置の保存/復元を追加（既存の仕組みを流用）
- [ ] `NoteWindowController.windowDidBecomeKey` で `NoteWebView.focus()` を呼ぶ
- [ ] `NSWorkspace.open` で外部リンクを開く

## 実装詳細

### editor-web/src/extensions/keymap.ts

```ts
import { EditorSelection, Transaction } from "@codemirror/state";
import { EditorView, KeyBinding } from "@codemirror/view";
import { postToSwift } from "../bridge";

function wrapSelection(view: EditorView, marker: string): boolean {
  const changes = view.state.changeByRange((range) => {
    const text = view.state.sliceDoc(range.from, range.to);
    const wrapped = `${marker}${text}${marker}`;
    return {
      changes: { from: range.from, to: range.to, insert: wrapped },
      range: EditorSelection.range(
        range.from + marker.length,
        range.to + marker.length,
      ),
    };
  });
  view.dispatch(view.state.update(changes, { scrollIntoView: true }));
  return true;
}

function toggleTaskAtCursor(view: EditorView): boolean {
  const line = view.state.doc.lineAt(view.state.selection.main.head);
  const match = line.text.match(/^(\s*[-*+]\s+)\[( |x)\]/);
  if (!match) return false;
  const bracketStart = line.from + match[1].length + 1;
  const currentChar = match[2];
  const nextChar = currentChar === " " ? "x" : " ";
  view.dispatch({
    changes: { from: bracketStart, to: bracketStart + 1, insert: nextChar },
  });
  return true;
}

function openLinkAtCursor(view: EditorView): boolean {
  // カーソル位置のリンクノードを探して Swift に通知
  // 実装詳細は syntaxTree を利用（省略）
  return true;
}

export const chiramiKeymap: KeyBinding[] = [
  { key: "Mod-b", run: (view) => wrapSelection(view, "**") },
  { key: "Mod-i", run: (view) => wrapSelection(view, "*") },
  { key: "Mod-l", run: toggleTaskAtCursor },
  {
    key: "Mod-Equal",
    run: () => {
      postToSwift({ type: "fontSizeChange", delta: 1 });
      return true;
    },
  },
  {
    key: "Mod-Minus",
    run: () => {
      postToSwift({ type: "fontSizeChange", delta: -1 });
      return true;
    },
  },
  { key: "Mod-Enter", run: openLinkAtCursor },
];
```

### editor-web/src/extensions/checkbox.ts

```ts
import { syntaxTree } from "@codemirror/language";
import { Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
  WidgetType,
} from "@codemirror/view";

class CheckboxWidget extends WidgetType {
  constructor(private checked: boolean, private pos: number) {
    super();
  }

  eq(other: CheckboxWidget): boolean {
    return other.checked === this.checked && other.pos === this.pos;
  }

  toDOM(view: EditorView): HTMLElement {
    const wrap = document.createElement("span");
    wrap.className = "cm-checkbox-widget";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = this.checked;
    input.addEventListener("mousedown", (e) => e.preventDefault());
    input.addEventListener("click", (e) => {
      e.stopPropagation();
      const nextChar = this.checked ? " " : "x";
      view.dispatch({
        changes: { from: this.pos, to: this.pos + 1, insert: nextChar },
      });
    });
    wrap.appendChild(input);
    return wrap;
  }

  ignoreEvent(): boolean {
    return false;
  }
}

class CheckboxPlugin {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged) {
      this.decorations = this.build(update.view);
    }
  }

  private build(view: EditorView): DecorationSet {
    const decorations: Range<Decoration>[] = [];
    for (const { from, to } of view.visibleRanges) {
      syntaxTree(view.state).iterate({
        from,
        to,
        enter: (node) => {
          if (node.name !== "Task") return;
          // Task ノードは "[ ]" または "[x]" を含む
          const taskText = view.state.sliceDoc(node.from, node.to);
          const match = taskText.match(/\[( |x)\]/);
          if (!match) return;
          const bracketStart = node.from + match.index!;
          const checked = match[1] === "x";
          decorations.push(
            Decoration.replace({
              widget: new CheckboxWidget(checked, bracketStart + 1),
            }).range(bracketStart, bracketStart + 3),
          );
        },
      });
    }
    return Decoration.set(decorations, true);
  }
}

export const checkboxExtension = ViewPlugin.fromClass(CheckboxPlugin, {
  decorations: (v) => v.decorations,
});
```

**注意**: `@lezer/markdown` の Task ノードの正確な構造は `npm install` 後に確認すること。上のコードは構造の例示で、実際のノード名 (`TaskMarker` 等) に合わせて調整する。

### editor-web/src/editor.ts 更新

```ts
import { history, historyKeymap, defaultKeymap } from "@codemirror/commands";
import { search, searchKeymap } from "@codemirror/search";
import { keymap } from "@codemirror/view";
import { chiramiKeymap } from "./extensions/keymap";
import { checkboxExtension } from "./extensions/checkbox";

// extensions に追加
[
  history(),
  search(),
  keymap.of([
    ...chiramiKeymap,
    ...defaultKeymap,
    ...historyKeymap,
    ...searchKeymap,
  ]),
  checkboxExtension,
  // ...
]
```

`chiramiKeymap` は `defaultKeymap` より前に置き、カスタムバインディングが優先されるようにする。

### カーソル・スクロール変更通知

```ts
// main.ts または editor.ts 内
let cursorDebounce: number | null = null;
let scrollDebounce: number | null = null;

EditorView.updateListener.of((update) => {
  if (update.selectionSet) {
    if (cursorDebounce !== null) window.clearTimeout(cursorDebounce);
    cursorDebounce = window.setTimeout(() => {
      const head = update.state.selection.main.head;
      const line = update.state.doc.lineAt(head).number;
      postToSwift({ type: "cursorChanged", offset: head, line });
      cursorDebounce = null;
    }, 1000);
  }
  if (update.geometryChanged || update.viewportChanged) {
    if (scrollDebounce !== null) window.clearTimeout(scrollDebounce);
    scrollDebounce = window.setTimeout(() => {
      postToSwift({
        type: "scrollChanged",
        offset: view.scrollDOM.scrollTop,
      });
      scrollDebounce = null;
    }, 1000);
  }
});
```

### Swift 側: メッセージハンドラ追加

```swift
// NoteWebViewBridge.swift 内の switch
case "cursorChanged":
    if let offset = body["offset"] as? Int, let line = body["line"] as? Int {
        onCursorChanged?(offset, line)
    }
case "scrollChanged":
    if let offset = body["offset"] as? Double {
        onScrollChanged?(offset)
    }
case "openLink":
    if let urlString = body["url"] as? String, let url = URL(string: urlString) {
        NSWorkspace.shared.open(url)
    }
case "fontSizeChange":
    if let delta = body["delta"] as? Int {
        onFontSizeChange?(delta)
    }
```

`NoteWindowController` が `onFontSizeChange` を受けて `AppConfig` のフォントサイズを更新し、再注入する。

### 位置復元

```swift
// NoteWebView.swift
func setCursorPosition(offset: Int) {
    enqueueOrEval("window.chirami.setCursorPosition(\(offset));")
}

func setScrollPosition(offset: Double) {
    enqueueOrEval("window.chirami.setScrollPosition(\(offset));")
}

func focus() {
    enqueueOrEval("window.chirami.focus();")
}
```

```ts
// main.ts 内
exposeApi({
  // ...
  setCursorPosition: (offset: number) => {
    view.dispatch({ selection: { anchor: offset } });
  },
  setScrollPosition: (offset: number) => {
    view.scrollDOM.scrollTop = offset;
  },
  focus: () => view.focus(),
});
```

## 動作確認手順

1. Cmd+B / Cmd+I で選択範囲が装飾される
2. Cmd+L で現在行のチェックボックスがトグルされる
3. チェックボックスをクリックしてトグルできる
4. Cmd+F で検索ウィジェットが表示される
5. Cmd++ / Cmd+- でフォントサイズが変わる
6. Cmd+Enter でリンクが外部ブラウザで開く
7. カーソル位置が `state.yaml` に保存される
8. ウィンドウを閉じて再表示するとカーソル位置・スクロール位置が復元される
9. 外部ファイル変更後もカーソル位置が保持される（ただし新しいドキュメント長を超えたら末尾）
10. Undo/Redo が動作する
11. **全操作でクラッシュしない**

## 終了条件

- [ ] すべてのキーボードショートカットが動作する
- [ ] チェックボックスクリックが動作する
- [ ] カーソル・スクロール位置が `state.yaml` に保存される
- [ ] 復元時にカーソル・スクロール位置が戻る
- [ ] Undo/Redo が動作する
- [ ] 検索が動作する
- [ ] クラッシュしない

## 想定されるリスク

### リスク 1: Cmd+L のキーバインディングが CodeMirror デフォルトと競合

**内容**: `@codemirror/commands` の `defaultKeymap` に `Mod-l` が既にある場合（行選択等）、上書きが必要。

**対策**:

- `chiramiKeymap` を `defaultKeymap` より前に置く
- `defaultKeymap` から `Mod-l` を除外して使う

### リスク 2: チェックボックス widget の Task ノード構造の誤認

**内容**: `@lezer/markdown` の GFM 拡張の Task ノード構造が想定と異なる場合がある。

**対策**:

- `npm install` 後、開発コンソールで `syntaxTree` を dump してノード構造を確認
- 正しいノード名（`Task` / `TaskMarker` 等）に合わせて修正

### リスク 3: カーソル位置のオフセット単位

**内容**: CodeMirror のオフセットは UTF-16 code unit。Swift の `String.count` は grapheme cluster なので変換が必要な場合がある。

**対策**:

- Swift 側で `NSString` または `String.utf16.count` を使う
- オフセット値は Int として JS ↔ Swift 間でそのまま扱う

### リスク 4: Undo 履歴と外部ファイル変更の競合

**内容**: 外部ファイル変更で `setContent` を呼ぶと Undo が期待通り動かないことがある。

**対策**:

- 外部変更での `setContent` は履歴をクリアせず、新しい変更として扱う
- Periodic Note のロールオーバー時のみ `clearHistory` を明示的に呼ぶ（Phase 6 で追加検討）

## Phase 6 への引き継ぎ事項

- `extensions/` ディレクトリが Phase 6 で追加される `image.ts` / `foldMarkdown.ts` / `smartPaste.ts` の置き場所になる
- キーマップは Phase 6 で paste ハンドラを追加する際に `EditorView.domEventHandlers` と組み合わせる
- カーソル・スクロール永続化の仕組みは折りたたみ状態の永続化（Phase 6）でも流用
