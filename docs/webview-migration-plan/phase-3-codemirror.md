# Phase 3: CodeMirror 導入とクラッシュ検証

## 目的

Phase 1・2 で安定動作している `<textarea>` ベースのエディタを CodeMirror 6 のベア構成に置き換え、**macOS 26.4 beta 環境で `contenteditable` + CodeMirror がクラッシュの原因かどうかを確定させる**。

**このフェーズは実装の前進と同時に、前回頓挫した原因を特定する検証フェーズでもある。** Go/No-go 判定は実機で慎重に行う。

## スコープ

### 含む

- `editor-web/` への CodeMirror 6 パッケージ追加
- `editor.ts` の新規作成（CodeMirror `EditorView` セットアップ、拡張なし）
- `main.ts` で `<textarea>` を CodeMirror に置き換え
- Phase 2 の CSS 変数を CodeMirror のセレクタに適用
- ブリッジ（`setContent` / `contentChanged` / `setTheme` / `setFont`）を CodeMirror に接続
- `ready` 通知を CodeMirror 初期化完了後に変更
- クラッシュ検証（1 キー入力・連続入力・IME・フォーカス切り替え）

### 含まない

- Markdown シンタックスハイライト（Phase 4）
- Live Preview のカーソル行判定（Phase 4）
- キーボードショートカット（Phase 5）
- 任意の拡張機能（Phase 4 以降）

## 使用する CodeMirror パッケージ

このフェーズでは最小限のみ。Phase 4 で Markdown 関連を追加する。

| パッケージ | 用途 |
|-----------|------|
| @codemirror/state | ドキュメント・選択・トランザクション |
| @codemirror/view | EditorView |

言語拡張・キーマップ・履歴・装飾はこのフェーズではまだ入れない。**ベア構成のまま** クラッシュを検証する。

## タスク一覧

- [x] `editor-web/package.json` に `@codemirror/state` `@codemirror/view` を追加
- [x] `npm install` 実行 → `node_modules/` 生成
- [x] `editor-web/src/editor.ts` 作成（EditorView セットアップのみ）
- [x] `editor-web/src/main.ts` を書き換え（textarea 削除・editor.ts 呼び出し）
- [x] `editor-web/index.html` の `<textarea>` を `<div id="editor"></div>` に変更
- [x] `editor-web/src/style.css` に CodeMirror セレクタ用の CSS を追加（Phase 2 の変数を流用）
- [x] ブリッジ API を CodeMirror 用に再実装
  - [x] `setContent` は `dispatch` で全置換
  - [x] `contentChanged` は `updateListener` で発火
- [x] `ready` 通知を CodeMirror 初期化後に移動
- [x] `mise run editor-build` でビルド成功を確認
- [x] 実機で起動 → クラッシュしないことを確認
- [x] **検証スクリプト**（下記）を実施
- [x] 検証結果を `docs/webkit-crash-investigation.md` に追記

## 実装詳細

### editor-web/package.json 更新

```json
{
  "dependencies": {
    "@codemirror/state": "^6",
    "@codemirror/view": "^6"
  }
}
```

esbuild の設定はそのまま（`--bundle` で CodeMirror を一括バンドル）。

### editor-web/index.html 更新

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <link rel="stylesheet" href="bundle.css" />
  </head>
  <body>
    <div id="editor"></div>
    <script src="bundle.js"></script>
  </body>
</html>
```

### editor-web/src/editor.ts

```ts
import { EditorState, Transaction } from "@codemirror/state";
import { EditorView, ViewUpdate } from "@codemirror/view";

export type EditorCallbacks = {
  onContentChanged: (text: string) => void;
};

export function createEditor(parent: HTMLElement, callbacks: EditorCallbacks): EditorView {
  const updateListener = EditorView.updateListener.of((update: ViewUpdate) => {
    if (update.docChanged) {
      callbacks.onContentChanged(update.state.doc.toString());
    }
  });

  const state = EditorState.create({
    doc: "",
    extensions: [
      updateListener,
      EditorView.contentAttributes.of({
        spellcheck: "false",
        autocorrect: "off",
        autocapitalize: "off",
      }),
    ],
  });

  return new EditorView({ state, parent });
}

export function setEditorContent(view: EditorView, text: string) {
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: text },
  });
}
```

`updateListener` で直接 `onContentChanged` を呼ぶ。debounce は JS 側で実装する。

### editor-web/src/main.ts 書き換え

```ts
import { createEditor, setEditorContent } from "./editor";
import { postToSwift, exposeApi } from "./bridge";
import { applyCSSVariables, applyFont } from "./theme";

const container = document.getElementById("editor")!;
let debounceTimer: number | null = null;
let suppressChangeNotification = false;

const view = createEditor(container, {
  onContentChanged: (text) => {
    if (suppressChangeNotification) return;
    if (debounceTimer !== null) window.clearTimeout(debounceTimer);
    debounceTimer = window.setTimeout(() => {
      postToSwift({ type: "contentChanged", text });
      debounceTimer = null;
    }, 300);
  },
});

exposeApi({
  setContent: (text) => {
    suppressChangeNotification = true;
    setEditorContent(view, text);
    suppressChangeNotification = false;
  },
  setTheme: applyCSSVariables,
  setFont: applyFont,
});

postToSwift({ type: "ready" });
```

### editor-web/src/style.css 追加

Phase 2 の変数定義はそのままに、CodeMirror のセレクタへのマッピングを追加する。

```css
html, body, #editor {
  margin: 0;
  padding: 0;
  height: 100%;
}

.cm-editor {
  height: 100%;
  background-color: var(--chirami-bg);
  color: var(--chirami-text);
  font-family: var(--chirami-font);
  font-size: var(--chirami-font-size);
}

.cm-editor.cm-focused {
  outline: none;
}

.cm-content {
  padding: 12px 16px;
  caret-color: var(--chirami-text);
  -webkit-font-smoothing: antialiased;
}

.cm-selectionBackground,
.cm-editor ::selection {
  background-color: var(--chirami-selection) !important;
}

.cm-scroller {
  line-height: 1.5;
}
```

## クラッシュ検証手順

Phase 3 の最重要ステップ。**以下の検証を順に実施し、どの操作で落ちるかを厳密に記録する。**

### 事前準備

1. `log stream --predicate 'subsystem == "com.apple.WebKit"' --level debug` を別ターミナルで起動
2. Console.app でクラッシュログ監視を有効化
3. アプリのビルドは Release 相当でなく Debug ビルドで実施（バックトレース取得のため）

### 検証シナリオ

| # | 操作 | 期待結果 | 結果記録欄 |
|---|------|----------|------------|
| 1 | アプリ起動のみ | クラッシュなし | |
| 2 | ノートを開く（フォーカスなし） | クラッシュなし | |
| 3 | エディタにフォーカス | クラッシュなし | |
| 4 | 半角英字を 1 回押して離す | クラッシュなし（最重要） | |
| 5 | 半角英字を押しっぱなし | クラッシュなし | |
| 6 | 日本語を IME 変換して確定 | クラッシュなし | |
| 7 | 連続で 100 文字程度入力 | クラッシュなし | |
| 8 | バックスペースで削除 | クラッシュなし | |
| 9 | マウスで選択 → コピー | クラッシュなし | |
| 10 | 選択 → ペースト | クラッシュなし | |
| 11 | ウィンドウサイズ変更 | クラッシュなし | |
| 12 | `setTheme` を連続実行 | クラッシュなし | |
| 13 | ノートを閉じて再表示 | クラッシュなし | |

### 結果の記録先

結果は `docs/webkit-crash-investigation.md` の末尾に「Phase 3 検証結果」節として追記する。前回の STEP 1〜3 の記録と並列に扱う。

## Go/No-go 判定

### Go 条件（Phase 4 に進む）

- 検証シナリオ 1〜13 すべてクラッシュなし
- 連続入力・IME 変換・`setTheme` の再注入でクラッシュなし
- 10 分以上の通常操作でクラッシュなし

### No-go 条件（Phase 1/2 で運用継続）

- いずれかの操作でクラッシュ再現
- クラッシュバックトレースが前回と同じ `swift_task_isMainExecutorImpl` / `RemoteLayerTreePropertyApplier::applyHierarchyUpdates`

### No-go 時の対応

1. `editor-web` / `NoteWebView` の実装は **feat/web-view2 ブランチに維持** する（破棄しない）
2. `main` ブランチには Phase 1・2 の `<textarea>` ベース実装のみマージ
3. `docs/webkit-crash-investigation.md` に Phase 3 の結果を追記
4. Apple Feedback を再提出（前回のケースに Phase 3 の結果を補足）
5. 次の macOS beta / GM でクラッシュが解消されたら Phase 3 以降を再開

## 想定されるリスク

### リスク 1: クラッシュが前回と同じ経路で再現

**内容**: 最も可能性の高いシナリオ。WebKit バグが OS 側で修正されていない限り発生する。

**対策**: 上記 No-go 時の対応に従う。慌てずに Phase 1/2 の暫定運用へ切り替える。

### リスク 2: クラッシュが前回と別の経路で発生

**内容**: ベア構成でも別経路で落ちる場合、WebKit バグが複数存在する可能性。

**対策**:

- 新しいバックトレースを取得し `webkit-crash-investigation.md` に追記
- 切り分けのため CodeMirror 拡張を 1 つずつ足して再現するか試す

### リスク 3: クラッシュはしないが入力時の挙動が不安定

**内容**: ちらつき・キャレット消失・IME 確定時の値ズレ等。

**対策**:

- Phase 3 では見た目の粗さは許容する。Phase 4・5 で調整
- ただし IME で値ズレがある場合は Phase 4 に進まず修正

### リスク 4: bundle.js のサイズ増加

**内容**: CodeMirror 2 パッケージだけでも 150〜200 KB になる。

**対策**:

- Phase 3 時点では minify + tree shaking のみで対応
- Phase 6 完了時点で 500 KB 以下を目標

## 終了条件

- [ ] CodeMirror ベア構成でエディタが起動する
- [ ] テキスト入力・保存が Phase 1 と同じく動作する
- [ ] Phase 2 のテーマ・フォント設定が CodeMirror にも反映される
- [ ] クラッシュ検証シナリオ 1〜13 すべて通過（Go 判定）
  - あるいは
- [ ] クラッシュ検証結果を `webkit-crash-investigation.md` に記録し、No-go 時の対応を完了

## Phase 4 への引き継ぎ事項

- `editor.ts` の拡張リストはここから機能追加していく
- `updateListener` による `contentChanged` 通知は Phase 4 以降もそのまま
- Phase 4 で `@codemirror/lang-markdown` を追加する際、bundle size の増加を記録
- クラッシュ検証は Phase 4・5 でも新しい拡張を追加した段階で再実施する（小規模で良い）
