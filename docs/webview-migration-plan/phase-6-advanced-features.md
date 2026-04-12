# Phase 6: 画像・テーブル・折りたたみ・Smart Paste

## 目的

NSTextView 版で実装されていた高度な機能（画像インライン表示・リサイズ・削除、テーブル HTML レンダリング、見出し折りたたみ、Smart Paste）を CodeMirror + WKWebView 版で再現する。

## 前提

- Phase 5 までの基本インタラクションが動作していること
- カーソル・スクロール永続化が動いていること

## スコープ

### 含む

- 画像 widget（インライン表示）
- 画像リサイズハンドル（マウスドラッグ）
- 画像削除ボタン（hover 時）
- `chirami-img://` custom scheme handler（Swift 側）
- セキュリティスコープドブックマーク経由の画像読み込み
- テーブル HTML レンダリング widget（非カーソル行では `<table>` に置換）
- 見出し折りたたみ（`@codemirror/language` の `foldService`）
- リスト折りたたみ
- 折りたたみ状態の永続化（`foldChanged` メッセージ → `state.yaml`）
- Smart Paste
  - 画像クリップボード → Swift で保存 → 挿入
  - HTML クリップボード → turndown で MD 変換 → 挿入
  - プレーンテキスト → そのまま挿入
- Cmd+Shift+V でプレーンテキスト強制ペースト

### 含まない

- テーブルセル移動（Tab キーによるセル間移動）
- リッチな図形の描画
- 旧実装の削除（Phase 7）

## タスク一覧

### テーブル widget

- [ ] `editor-web/src/extensions/table.ts` 作成
- [ ] `ViewPlugin` でテーブルブロックを検出（`Table` ノード）
- [ ] カーソルがテーブル外の行では `Decoration.replace` で `<table>` widget に置換
- [ ] `TableWidget` が GFM テーブルのテキストを HTML テーブルにパース・描画
- [ ] カーソルがテーブル内の行ではテーブル全体を raw Markdown に戻す（livePreview と同方式）
- [ ] CSS でテーブルのスタイルを定義（ボーダー・パディング・ヘッダー行）

### 画像 widget

- [ ] `editor-web/src/extensions/image.ts` 作成
- [ ] `WidgetType` で `<img>` を描画
- [ ] alt の `|width=...` 構文をパースして style に反映
- [ ] hover 時にリサイズハンドルと削除ボタンを表示
- [ ] リサイズドラッグ実装（`mousedown` / `mousemove` / `mouseup`）
- [ ] リサイズ確定時に Markdown の `|width` を更新
- [ ] 削除ボタンクリックで該当行の画像 markdown を削除
- [ ] 画像 src の解決（`chirami-img://` スキーム）

### Custom scheme handler

- [ ] `Chirami/Services/LocalImageSchemeHandler.swift` 作成
- [ ] `WKURLSchemeHandler` 実装
- [ ] セキュリティスコープドブックマーク取得（`NoteStore.shared.resolveBookmark`）
- [ ] FileHandle で読み込み → `urlSchemeTask.didReceive` で返却
- [ ] MIME type 判定
- [ ] `WKWebViewConfiguration.setURLSchemeHandler` で登録

### 折りたたみ

- [ ] `editor-web/src/extensions/foldMarkdown.ts` 作成
- [ ] `foldService` で見出しセクションを折りたたみ範囲として返す
- [ ] `foldGutter` を有効化（左側のクリック領域）
- [ ] リスト項目（深いインデント）の折りたたみ範囲
- [ ] 折りたたみ状態の `foldChanged` 通知
- [ ] Swift 側で `state.yaml` に保存
- [ ] 復元時に `foldEffect.of` で折りたたみを再適用

### Smart Paste

- [ ] `editor-web/package.json` に `turndown` `turndown-plugin-gfm` 追加
- [ ] `editor-web/src/extensions/smartPaste.ts` 作成
- [ ] `EditorView.domEventHandlers({ paste })` で paste をキャプチャ
- [ ] 画像 → `pasteImage` メッセージで Swift に送信
- [ ] HTML → `turndown` で MD 変換 → 挿入
- [ ] プレーンテキスト → そのまま挿入
- [ ] Cmd+Shift+V でプレーンテキスト強制
- [ ] Swift 側で画像保存ロジック実装（既存 `ImagePasteService` を流用）

## 実装詳細

### editor-web/src/extensions/table.ts（概要）

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

class TableWidget extends WidgetType {
  constructor(private markdown: string) {
    super();
  }

  eq(other: TableWidget): boolean {
    return other.markdown === this.markdown;
  }

  toDOM(): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "cm-table-widget";
    wrap.innerHTML = parseMarkdownTable(this.markdown);
    return wrap;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

function parseMarkdownTable(md: string): string {
  const lines = md.trim().split("\n");
  if (lines.length < 2) return md;

  const parseRow = (line: string) =>
    line.replace(/^\||\|$/g, "").split("|").map((c) => c.trim());

  const headers = parseRow(lines[0]);
  // lines[1] is the separator (--- | --- | ---)
  const rows = lines.slice(2).map(parseRow);

  const th = headers.map((h) => `<th>${h}</th>`).join("");
  const tbody = rows
    .map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join("")}</tr>`)
    .join("");
  return `<table><thead><tr>${th}</tr></thead><tbody>${tbody}</tbody></table>`;
}

class TablePlugin {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged || update.selectionSet) {
      this.decorations = this.build(update.view);
    }
  }

  private build(view: EditorView): DecorationSet {
    const cursorPos = view.state.selection.main.head;
    const cursorLine = view.state.doc.lineAt(cursorPos).number;
    const decorations: Range<Decoration>[] = [];

    for (const { from, to } of view.visibleRanges) {
      syntaxTree(view.state).iterate({
        from,
        to,
        enter: (node) => {
          if (node.name !== "Table") return;
          const startLine = view.state.doc.lineAt(node.from).number;
          const endLine = view.state.doc.lineAt(node.to).number;
          // Show raw Markdown when cursor is inside the table
          if (cursorLine >= startLine && cursorLine <= endLine) return;
          const tableMarkdown = view.state.sliceDoc(node.from, node.to);
          decorations.push(
            Decoration.replace({
              widget: new TableWidget(tableMarkdown),
              block: true,
            }).range(node.from, node.to),
          );
        },
      });
    }

    return Decoration.set(decorations, true);
  }
}

export const tableExtension = ViewPlugin.fromClass(TablePlugin, {
  decorations: (v) => v.decorations,
});
```

**CSS:**

```css
.cm-table-widget {
  overflow-x: auto;
  margin: 0.5em 0;
}

.cm-table-widget table {
  border-collapse: collapse;
  width: 100%;
  font-size: var(--chirami-font-size);
}

.cm-table-widget th,
.cm-table-widget td {
  border: 1px solid rgba(128, 128, 128, 0.3);
  padding: 4px 8px;
  text-align: left;
}

.cm-table-widget thead tr {
  background: rgba(128, 128, 128, 0.1);
  font-weight: bold;
}
```

**注意**: `parseMarkdownTable` はシンプルなパーサーで、アライメント指定（`:---:` など）は無視している。Phase 6 では対応しない。

### editor-web/src/extensions/image.ts（概要）

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

type ImageInfo = {
  src: string;
  alt: string;
  width: number | null;
  from: number;
  to: number;
};

class ImageWidget extends WidgetType {
  constructor(private info: ImageInfo) {
    super();
  }

  eq(other: ImageWidget): boolean {
    return (
      other.info.src === this.info.src &&
      other.info.width === this.info.width &&
      other.info.from === this.info.from
    );
  }

  toDOM(view: EditorView): HTMLElement {
    const wrap = document.createElement("span");
    wrap.className = "cm-image-widget";

    const img = document.createElement("img");
    img.src = resolveImageSrc(this.info.src);
    img.alt = this.info.alt;
    if (this.info.width !== null) img.style.width = `${this.info.width}px`;
    wrap.appendChild(img);

    const handle = document.createElement("div");
    handle.className = "cm-image-resize-handle";
    wrap.appendChild(handle);

    const deleteBtn = document.createElement("button");
    deleteBtn.className = "cm-image-delete";
    deleteBtn.textContent = "×";
    deleteBtn.addEventListener("click", () => {
      view.dispatch({
        changes: { from: this.info.from, to: this.info.to, insert: "" },
      });
    });
    wrap.appendChild(deleteBtn);

    this.attachResize(wrap, img, view);
    return wrap;
  }

  private attachResize(wrap: HTMLElement, img: HTMLImageElement, view: EditorView) {
    const handle = wrap.querySelector(".cm-image-resize-handle") as HTMLElement;
    let startX = 0;
    let startWidth = 0;
    let dragging = false;

    handle.addEventListener("mousedown", (e) => {
      e.preventDefault();
      dragging = true;
      startX = e.clientX;
      startWidth = img.offsetWidth;
    });

    window.addEventListener("mousemove", (e) => {
      if (!dragging) return;
      const newWidth = Math.max(50, startWidth + (e.clientX - startX));
      img.style.width = `${newWidth}px`;
    });

    window.addEventListener("mouseup", (e) => {
      if (!dragging) return;
      dragging = false;
      const newWidth = Math.max(50, startWidth + (e.clientX - startX));
      this.commitWidth(view, newWidth);
    });
  }

  private commitWidth(view: EditorView, width: number) {
    // Markdown のテキストを書き換え（alt の |width 指定を更新）
    const original = view.state.sliceDoc(this.info.from, this.info.to);
    const updated = updateImageWidth(original, width);
    view.dispatch({
      changes: { from: this.info.from, to: this.info.to, insert: updated },
    });
  }

  ignoreEvent(): boolean {
    return false;
  }
}

function resolveImageSrc(src: string): string {
  // 絶対 URL ならそのまま、相対パスなら chirami-img:// に変換
  if (/^https?:/.test(src)) return src;
  if (src.startsWith("data:")) return src;
  return `chirami-img://${encodeURI(src)}`;
}

function updateImageWidth(markdown: string, width: number): string {
  // ![alt|width](url) のような構文を更新
  return markdown.replace(/!\[([^\]]*?)(?:\|\d+)?\]/, (_, alt) => `![${alt}|${width}]`);
}

// ViewPlugin 部分は checkbox.ts と同じパターン
```

### Chirami/Services/LocalImageSchemeHandler.swift

```swift
import WebKit
import os
import UniformTypeIdentifiers

@MainActor
final class LocalImageSchemeHandler: NSObject, WKURLSchemeHandler {
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "LocalImageSchemeHandler")

    nonisolated func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "Chirami", code: -1))
            return
        }

        // chirami-img://relative/path/to/image.png
        let path = url.host.flatMap { _ in url.path } ?? url.path
        let decoded = path.removingPercentEncoding ?? path

        Task { @MainActor in
            do {
                let data = try await self.loadImage(at: decoded)
                let mime = self.mimeType(for: decoded)
                let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                self.logger.error("failed to load image: \(error.localizedDescription, privacy: .public)")
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func loadImage(at path: String) async throws -> Data {
        // NoteStore のセキュリティスコープドブックマーク機構を流用
        let url = NoteStore.shared.resolveImageURL(path) ?? URL(fileURLWithPath: path)
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private func mimeType(for path: String) -> String {
        if let type = UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType {
            return type
        }
        return "application/octet-stream"
    }
}
```

`NoteStore.resolveImageURL(_:)` は既存の画像パス解決ロジックがあれば流用、なければ新規追加する。

### NoteWebView.swift で scheme handler を登録

```swift
init(frame frameRect: NSRect) {
    let config = WKWebViewConfiguration()
    // ...
    config.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: "chirami-img")
    // ...
}
```

### editor-web/src/extensions/foldMarkdown.ts

```ts
import { foldService } from "@codemirror/language";

export const markdownFold = foldService.of((state, lineStart, lineEnd) => {
  const line = state.doc.lineAt(lineStart);
  const headingMatch = line.text.match(/^(#{1,6})\s/);
  if (headingMatch) {
    const level = headingMatch[1].length;
    // 次の同レベル以上の見出しまでを折りたたみ範囲とする
    let endLine = state.doc.lines;
    for (let n = line.number + 1; n <= state.doc.lines; n++) {
      const next = state.doc.line(n);
      const nextMatch = next.text.match(/^(#{1,6})\s/);
      if (nextMatch && nextMatch[1].length <= level) {
        endLine = n - 1;
        break;
      }
    }
    if (endLine > line.number) {
      return { from: line.to, to: state.doc.line(endLine).to };
    }
  }
  return null;
});
```

折りたたみ状態の永続化:

```ts
// editor.ts
import { foldEffect, foldedRanges } from "@codemirror/language";

EditorView.updateListener.of((update) => {
  if (update.transactions.some((t) => t.effects.some((e) => e.is(foldEffect)))) {
    const folded: Array<{ from: number; to: number }> = [];
    foldedRanges(update.state).between(0, update.state.doc.length, (from, to) => {
      folded.push({ from, to });
    });
    postToSwift({ type: "foldChanged", folded });
  }
});
```

### editor-web/src/extensions/smartPaste.ts

```ts
import { EditorView } from "@codemirror/view";
import TurndownService from "turndown";
import { gfm } from "turndown-plugin-gfm";
import { postToSwift } from "../bridge";

const turndown = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced" });
turndown.use(gfm);

export const smartPaste = EditorView.domEventHandlers({
  paste(event, view) {
    const data = event.clipboardData;
    if (!data) return false;

    // 1. 画像
    const imageItem = Array.from(data.items).find((it) => it.type.startsWith("image/"));
    if (imageItem) {
      const file = imageItem.getAsFile();
      if (file) {
        event.preventDefault();
        const reader = new FileReader();
        reader.onload = () => {
          const dataUrl = reader.result as string;
          postToSwift({ type: "pasteImage", dataUrl });
        };
        reader.readAsDataURL(file);
        return true;
      }
    }

    // 2. HTML
    const html = data.getData("text/html");
    if (html) {
      event.preventDefault();
      const md = turndown.turndown(html);
      view.dispatch(view.state.replaceSelection(md));
      return true;
    }

    // 3. プレーンテキスト → デフォルト処理
    return false;
  },
});
```

Swift 側の `pasteImage` ハンドラ:

```swift
case "pasteImage":
    if let dataUrl = body["dataUrl"] as? String {
        Task { @MainActor in
            if let insertText = await self.imagePasteService.savePastedImage(dataUrl: dataUrl) {
                self.onPasteImageResolved?(insertText)
            }
        }
    }
```

`onPasteImageResolved` で `NoteWebView.insertMarkdown(text)` のような新 API を呼んで JS 側に挿入する。

## CSS 追加

```css
.cm-image-widget {
  position: relative;
  display: inline-block;
}

.cm-image-widget img {
  display: block;
  max-width: 100%;
  border-radius: 4px;
}

.cm-image-resize-handle {
  position: absolute;
  right: -4px;
  bottom: -4px;
  width: 12px;
  height: 12px;
  background: rgba(0, 0, 0, 0.3);
  border-radius: 50%;
  cursor: nwse-resize;
  opacity: 0;
  transition: opacity 0.15s;
}

.cm-image-widget:hover .cm-image-resize-handle,
.cm-image-widget:hover .cm-image-delete {
  opacity: 1;
}

.cm-image-delete {
  position: absolute;
  top: 4px;
  right: 4px;
  width: 20px;
  height: 20px;
  border: none;
  background: rgba(0, 0, 0, 0.6);
  color: white;
  border-radius: 50%;
  cursor: pointer;
  opacity: 0;
}
```

## 動作確認手順

### テーブル

1. テーブルを含むノートを開く → カーソルがテーブル外では HTML テーブルとして表示される
2. テーブル行にカーソルを移動 → raw Markdown に戻る
3. テーブル外にカーソルを移動 → 再び HTML テーブルに戻る
4. ヘッダー行が太字・背景色で区別されている

### 画像

1. `![alt](image.png)` を含むノートを開く → 画像がインライン表示される
2. 画像にホバー → リサイズハンドルと削除ボタンが表示される
3. リサイズハンドルをドラッグ → サイズが変わる
4. ドラッグ終了後 → ノートの Markdown に `|width=N` が反映される
5. 削除ボタンをクリック → 画像 markdown が削除される
6. HTTP 画像も表示される（外部 URL）
7. セキュリティスコープドブックマークが必要なファイルも表示される

### 折りたたみ

1. 見出しを含むノートを開く → gutter にトグルアイコンが表示される
2. クリックでセクション折りたたみ
3. ノートを閉じて再表示 → 折りたたみ状態が復元される
4. リスト項目の折りたたみも動作する

### Smart Paste

1. ブラウザで画像をコピー → ノートにペースト → 画像が保存され markdown が挿入される
2. ブラウザで HTML テキストをコピー → ペースト → Markdown 変換されて挿入される
3. プレーンテキストをコピー → ペースト → そのまま挿入される
4. Cmd+Shift+V → HTML でもプレーンテキストとして挿入される

## 終了条件

- [ ] テーブルが HTML レンダリングされる
- [ ] カーソルがテーブル内では raw Markdown に戻る
- [ ] 画像インライン表示・リサイズ・削除がすべて動作する
- [ ] `chirami-img://` で sandbox 下の画像が読める
- [ ] 見出しとリストの折りたたみが動作する
- [ ] 折りたたみ状態が永続化される
- [ ] Smart Paste（画像・HTML・プレーン）が動作する
- [ ] Cmd+Shift+V でプレーンテキスト強制ができる
- [ ] クラッシュしない

## 想定されるリスク

### リスク 1: WKURLSchemeHandler のメインアクター制約

**内容**: `WKURLSchemeHandler` は通常バックグラウンドスレッドから呼ばれるが、`NoteStore.shared` などはメインアクター隔離されている。

**対策**:

- `nonisolated func` で受けて `Task { @MainActor in ... }` で処理
- `urlSchemeTask` の応答も `MainActor` 上で実行（実装例参照）

### リスク 2: 画像リサイズの滑らかさ

**内容**: `mousemove` ベースのドラッグが ResizeObserver や CodeMirror の再レイアウトと競合する可能性。

**対策**:

- `requestAnimationFrame` でドラッグを 1 フレームに 1 回に制限
- ドラッグ中は `view.dispatch` を呼ばず、`mouseup` 時にだけ反映

### リスク 3: turndown のバンドルサイズ

**内容**: turndown + GFM プラグインで 50〜80 KB 程度追加。

**対策**:

- esbuild の minify で削減
- 全体で 500 KB 以下に収まれば許容

### リスク 4: 折りたたみ範囲の永続化と外部変更の整合性

**内容**: 外部ファイル変更で行番号がズレると折りたたみ範囲が無意味になる。

**対策**:

- `setContent` 時に `foldedRanges` をクリア
- ユーザーが folded 状態を再構築する形にする
- もしくは行内容のハッシュで対応関係を再構築（複雑なので Phase 6 では実装しない）

### リスク 5: paste イベントの優先順位

**内容**: CodeMirror 標準の paste ハンドラとカスタムハンドラが競合する。

**対策**:

- `EditorView.domEventHandlers` は標準ハンドラの前に呼ばれる
- `event.preventDefault()` を呼べば標準処理はスキップされる

## Phase 7 への引き継ぎ事項

- すべての機能が WebView 版で揃った状態。Phase 7 は旧実装の削除に集中
- 追加した依存（`turndown`, `turndown-plugin-gfm`）は Phase 7 では削除しない
- Swift 側の旧画像処理ロジック（`ImageCache.swift` 等）の用途を再評価して Phase 7 で削除可否を判断
