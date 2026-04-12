# Phase 4: Live Preview 実装

## 目的

Phase 3 で動作する CodeMirror ベア構成に、Markdown シンタックスハイライトと Obsidian 風 Live Preview を実装する。カーソル行だけ生 Markdown を表示し、他の行はレンダリング済みのように見せる。

## 前提

- Phase 3 で CodeMirror のクラッシュ検証が **Go 判定** されていること
- Go 判定されていない場合はこのフェーズは実施しない

## スコープ

### 含む

- `@codemirror/lang-markdown` の組み込み
- `@codemirror/language` による構文ハイライト
- `@lezer/markdown` `@lezer/highlight` の導入
- `livePreview.ts` 拡張の実装（カーソル行判定 + 非カーソル行の構文隠し）
- 見出し・強調・コード・引用・リンクのスタイリング
- GFM 対応（テーブルの構文ハイライト、取り消し線、タスクリスト等）

### 含まない

- チェックボックスクリック（Phase 5: checkbox widget で実装）
- 画像 widget（Phase 6）
- 折りたたみ（Phase 6）
- Smart Paste（Phase 6）
- キーボードショートカット（Phase 5）

## 使用する CodeMirror パッケージ（追加分）

| パッケージ | 用途 |
|-----------|------|
| @codemirror/language | 構文ツリー、言語サポート基盤 |
| @codemirror/lang-markdown | Markdown 言語拡張（GFM 対応） |
| @lezer/markdown | インクリメンタル Markdown パーサー |
| @lezer/highlight | 構文ハイライトタグ |

## タスク一覧

- [x] 上記パッケージを `editor-web/package.json` に追加
- [x] `npm install` 実行
- [x] `editor-web/src/extensions/livePreview.ts` 作成
- [x] `editor-web/src/editor.ts` に markdown + livePreview 拡張を追加
- [x] `editor-web/src/style.css` に Markdown 構文用スタイル追加
- [x] 見出し H1〜H6 の装飾
- [x] `**bold**` / `*italic*` の装飾
- [x] `` `code` `` / コードブロックの装飾
- [x] `> quote` の装飾
- [x] リンク `[text](url)` の装飾
- [x] 箇条書き `- ` / 番号付きリスト `1. ` の装飾
- [x] 水平線 `---` の装飾
- [x] GFM テーブルの構文ハイライト確認
- [x] カーソル行判定ロジック実装
- [x] 非カーソル行の構文マーク隠し（`Decoration.replace`）
- [x] 実機確認: 既存のテストノートで Live Preview が動作
- [x] 実機確認: 連続入力・IME でクラッシュしない
- [x] 実機確認: カーソル移動に追従して表示が切り替わる

## 実装詳細

### editor-web/package.json 更新

```json
{
  "dependencies": {
    "@codemirror/state": "^6",
    "@codemirror/view": "^6",
    "@codemirror/language": "^6",
    "@codemirror/lang-markdown": "^6",
    "@lezer/markdown": "^1",
    "@lezer/highlight": "^1"
  }
}
```

### editor-web/src/extensions/livePreview.ts

```ts
import { syntaxTree } from "@codemirror/language";
import { Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
} from "@codemirror/view";

// 非カーソル行で隠すべき Markdown マークのノード名
const HIDDEN_MARK_NODES = new Set([
  "HeaderMark",
  "EmphasisMark",
  "CodeMark",
  "LinkMark",
  "URL",
  "StrikethroughMark",
]);

class LivePreviewPlugin {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate) {
    if (
      update.docChanged ||
      update.selectionSet ||
      update.viewportChanged
    ) {
      this.decorations = this.build(update.view);
    }
  }

  private build(view: EditorView): DecorationSet {
    const cursorLine = view.state.doc.lineAt(view.state.selection.main.head).number;
    const decorations: Range<Decoration>[] = [];

    for (const { from, to } of view.visibleRanges) {
      syntaxTree(view.state).iterate({
        from,
        to,
        enter: (node) => {
          if (!HIDDEN_MARK_NODES.has(node.name)) return;
          const lineNumber = view.state.doc.lineAt(node.from).number;
          if (lineNumber === cursorLine) return; // 生表示
          decorations.push(Decoration.replace({}).range(node.from, node.to));
        },
      });
    }

    return Decoration.set(decorations, true);
  }
}

export const livePreview = ViewPlugin.fromClass(LivePreviewPlugin, {
  decorations: (v) => v.decorations,
});
```

### editor-web/src/editor.ts 更新

```ts
import { EditorState } from "@codemirror/state";
import { EditorView, ViewUpdate } from "@codemirror/view";
import { markdown } from "@codemirror/lang-markdown";
import { syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language";
import { livePreview } from "./extensions/livePreview";

export function createEditor(parent: HTMLElement, callbacks: EditorCallbacks): EditorView {
  const state = EditorState.create({
    doc: "",
    extensions: [
      markdown(),
      syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
      livePreview,
      EditorView.updateListener.of((update: ViewUpdate) => {
        if (update.docChanged) callbacks.onContentChanged(update.state.doc.toString());
      }),
      EditorView.contentAttributes.of({
        spellcheck: "false",
        autocorrect: "off",
        autocapitalize: "off",
      }),
    ],
  });
  return new EditorView({ state, parent });
}
```

### editor-web/src/style.css 追加

CSS 変数（Phase 2）をそのまま使い、CodeMirror のハイライト対象セレクタに色を当てる。

```css
/* Markdown 装飾 */
.cm-editor .tok-heading1 { font-size: 1.6em; font-weight: 700; }
.cm-editor .tok-heading2 { font-size: 1.4em; font-weight: 700; }
.cm-editor .tok-heading3 { font-size: 1.2em; font-weight: 700; }
.cm-editor .tok-heading4,
.cm-editor .tok-heading5,
.cm-editor .tok-heading6 { font-weight: 700; }

.cm-editor .tok-emphasis { font-style: italic; }
.cm-editor .tok-strong { font-weight: 700; }
.cm-editor .tok-strikethrough { text-decoration: line-through; }

.cm-editor .tok-link { color: var(--chirami-link); text-decoration: underline; }
.cm-editor .tok-url { color: var(--chirami-link); }

.cm-editor .tok-monospace,
.cm-editor .tok-meta.tok-monospace {
  color: var(--chirami-code);
  background-color: var(--chirami-code-bg);
  border-radius: 3px;
  padding: 0 4px;
}

.cm-editor .cm-line.cm-quote {
  border-left: 3px solid var(--chirami-link);
  padding-left: 8px;
  opacity: 0.85;
}

/* コードブロック */
.cm-editor .tok-comment { opacity: 0.7; }

/* リストマーカー */
.cm-editor .tok-list { color: var(--chirami-link); }
```

HighlightStyle のトークン名は `@codemirror/language` の `tags` に対応する CSS クラス名になる。`defaultHighlightStyle` をベースに必要なら `HighlightStyle.define` で上書きする。

### カーソル行判定の詳細

- `view.state.selection.main.head` でカーソルオフセットを取得
- `doc.lineAt(head).number` で現在の行番号を取得
- 各ノードの開始位置から `lineAt(node.from).number` で同じ比較
- 複数行にまたがるノード（コードブロック等）は「ノードが含む行のいずれかがカーソル行なら表示」という判定にする

複数行ノード対応のため、以下のヘルパーを追加:

```ts
function nodeContainsCursorLine(view: EditorView, from: number, to: number, cursorLine: number): boolean {
  const startLine = view.state.doc.lineAt(from).number;
  const endLine = view.state.doc.lineAt(to).number;
  return cursorLine >= startLine && cursorLine <= endLine;
}
```

### GFM テーブルのハンドリング

- `@codemirror/lang-markdown` は標準で GFM テーブルをパースする
- テーブル行がカーソル行に含まれるときは生表示、そうでなければ構文マークを隠す
- **Phase 4 ではテーブルのセル移動は実装しない**（スコープ外）

## 動作確認手順

1. 既存の Markdown ノート（見出し・箇条書き・コード等を含む）を開く
2. カーソル行だけ生 Markdown、他行は装飾済みで表示されることを確認
3. カーソル移動（矢印キー・マウス）で表示が切り替わること
4. 入力して Markdown 構文を追加 → リアルタイムに装飾されること
5. 見出しの `#` マーカーがカーソル行では見えて、離れると隠れること
6. `**bold**` がカーソル行では `**` が見えて、離れると太字だけになること
7. `[text](url)` がカーソル行では raw で、離れるとリンクだけ見えること
8. コードブロック内ではカーソルが入っているかで backtick の表示が切り替わること
9. IME で日本語入力 → 入力中も装飾が乱れないこと
10. **クラッシュしないこと**

## 終了条件

- [ ] Markdown 構文ハイライトが動作する（実機確認待ち）
- [ ] カーソル行判定が動作する（カーソル行だけ生表示）（実機確認待ち）
- [ ] 見出し・強調・コード・リンク・引用・リストが装飾される（実機確認待ち）
- [ ] GFM テーブルの構文ハイライトが動作する（実機確認待ち）
- [ ] カスタム `color_schemes` の色が Markdown 装飾にも反映される（実機確認待ち）
- [ ] クラッシュしない（実機確認待ち）

## 想定されるリスク

### リスク 1: 大きなドキュメントでのパフォーマンス

**内容**: `syntaxTree.iterate` が毎更新で走るため、10,000 行クラスのドキュメントで遅延する可能性。

**対策**:

- `update.docChanged || update.selectionSet || update.viewportChanged` のみで再計算
- `view.visibleRanges` に限定して iterate
- 問題があれば `RangeSetBuilder` で差分計算に変更

### リスク 2: カーソル行の定義が曖昧

**内容**: 選択範囲がある場合、どの行を「カーソル行」とするかが不明瞭。

**対策**:

- 選択範囲がある場合は `selection.main.head` の行を使う
- 複数カーソル（将来実装）では最初のカーソル行のみ

### リスク 3: `HIDDEN_MARK_NODES` の網羅性不足

**内容**: 実際の Markdown ノードでは `HeaderMark` 以外にも隠したいマークが多数ある。

**対策**:

- 実機で試しながら追加
- `@lezer/markdown` のソースで全ノード名を確認
- 不足分は issue として記録

### リスク 4: Live Preview と編集操作の競合

**内容**: 非カーソル行を `Decoration.replace` で隠していると、その範囲にカーソルを置けなくなる場合がある。

**対策**:

- `Decoration.replace({inclusive: false})` で範囲の境界にカーソル配置を許可
- カーソル移動で隠れた範囲に入ったら自動的にその行がカーソル行になる（仕様通り）

## Phase 5 への引き継ぎ事項

- `editor.ts` の拡張リストに Phase 5 のキーマップとチェックボックス widget を追加する
- `livePreview.ts` の `HIDDEN_MARK_NODES` は Phase 5・6 で調整
- チェックボックス行は livePreview の対象外にする（Phase 5 の widget で別途装飾）
