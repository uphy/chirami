# Phase 1: textarea WebView と基盤ブリッジ

## 目的

WKWebView 自体と Swift ↔ JS ブリッジが macOS 26.4 beta 環境でクラッシュなく動作することを確認する。同時に、テキスト編集・保存・外部変更同期という基本機能を最低限のコード量で完成させる。

`<textarea>` を使うのは以下の理由から。

- `contenteditable` を使わないため、前回のクラッシュ調査で疑われている WebKit バグの経路を避けられる
- CodeMirror 未導入の状態でブリッジ・保存・ファイルウォッチャーを確立できる
- Phase 3 で CodeMirror を導入したときにクラッシュが出れば、CodeMirror 固有の問題と確定できる

## スコープ

### 含む

- `editor-web/` ディレクトリのセットアップ（npm + esbuild + TypeScript）
- `<textarea>` のみを含む HTML/CSS/JS
- `NoteWebView.swift`（WKWebView ラッパー）
- `NoteWebViewBridge.swift`（メッセージハンドラ）
- `NoteWindow.swift` からの呼び出し切り替え
- ブリッジメッセージ: `setContent` / `contentChanged` / `ready`
- debounce 300ms での自動保存
- 外部ファイル変更の同期（`NoteStore` のファイルウォッチャー → `setContent`）

### 含まない

- テーマ・フォント（Phase 2）
- Markdown パース・シンタックスハイライト（Phase 3 以降）
- カーソル/スクロール位置の永続化（Phase 5）
- キーボードショートカット（Phase 5）
- 画像・チェックボックス・折りたたみ（Phase 5・6）
- Smart Paste（Phase 6）
- 旧実装の削除（Phase 7）

## タスク一覧

- [x] `editor-web/package.json` 作成（esbuild + TypeScript のみ）
- [x] `editor-web/tsconfig.json` 作成
- [x] `editor-web/index.html` 作成（`<textarea>` のみ）
- [x] `editor-web/src/main.ts` 作成（ブリッジ初期化 + `<textarea>` 接続）
- [x] `editor-web/src/bridge.ts` 作成（Swift ↔ JS メッセージング）
- [x] `editor-web/src/style.css` 作成（`<textarea>` の最低限の見た目）
- [x] `editor-web/scripts/copy-html.js` 作成（index.html をビルド先にコピー）
- [x] `editor-web/.gitignore` で `node_modules/` を除外
- [x] `Chirami/Resources/editor/` ディレクトリ作成（初回ビルドで成果物が入る）
- [x] `Chirami/Views/NoteWebView.swift` 作成
- [x] `Chirami/Services/NoteWebViewBridge.swift` 作成
- [x] `Chirami/Views/NoteWindow.swift` を修正し `NoteWebView` を使用
- [x] `project.yml`: `sources: path: Chirami` で xcodegen が自動認識するため明示追加不要
- [x] `.mise/tasks/build/editor` 追加（`editor-build.sh` の代わりに `build/editor` として配置）
- [x] `xcodegen generate` → ビルド・実機確認

## 実装詳細

### editor-web/package.json

```json
{
  "name": "chirami-editor-web",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "build": "esbuild src/main.ts --bundle --minify --sourcemap --outfile=../Chirami/Resources/editor/bundle.js && esbuild src/style.css --bundle --minify --outfile=../Chirami/Resources/editor/bundle.css && node scripts/copy-html.js",
    "dev": "esbuild src/main.ts --bundle --watch --outfile=../Chirami/Resources/editor/bundle.js"
  },
  "devDependencies": {
    "esbuild": "^0.21",
    "typescript": "^5"
  }
}
```

### editor-web/tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "noEmit": true,
    "lib": ["ES2022", "DOM"]
  },
  "include": ["src/**/*.ts"]
}
```

### editor-web/index.html

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <link rel="stylesheet" href="bundle.css" />
  </head>
  <body>
    <textarea id="editor" spellcheck="false" autocomplete="off" autocapitalize="off"></textarea>
    <script src="bundle.js"></script>
  </body>
</html>
```

### editor-web/src/bridge.ts

```ts
// Swift → JS で呼ばれる API と、JS → Swift のメッセージ送信を定義
type SwiftToJsApi = {
  setContent: (text: string) => void;
};

type JsToSwiftMessage =
  | { type: "ready" }
  | { type: "contentChanged"; text: string }
  | { type: "log"; level: "debug" | "info" | "warn" | "error"; message: string };

declare global {
  interface Window {
    webkit?: {
      messageHandlers: {
        chirami: {
          postMessage: (msg: JsToSwiftMessage) => void;
        };
      };
    };
    chirami: SwiftToJsApi;
  }
}

export function postToSwift(msg: JsToSwiftMessage) {
  window.webkit?.messageHandlers.chirami.postMessage(msg);
}

export function exposeApi(api: SwiftToJsApi) {
  window.chirami = api;
}
```

### editor-web/src/main.ts

```ts
import { postToSwift, exposeApi } from "./bridge";

const editor = document.getElementById("editor") as HTMLTextAreaElement;
let debounceTimer: number | null = null;
let suppressNextInput = false;

exposeApi({
  setContent: (text: string) => {
    suppressNextInput = true;
    editor.value = text;
    suppressNextInput = false;
  },
});

editor.addEventListener("input", () => {
  if (suppressNextInput) return;
  if (debounceTimer !== null) {
    window.clearTimeout(debounceTimer);
  }
  debounceTimer = window.setTimeout(() => {
    postToSwift({ type: "contentChanged", text: editor.value });
    debounceTimer = null;
  }, 300);
});

// 初期化完了を Swift に通知
postToSwift({ type: "ready" });
```

### editor-web/src/style.css

```css
html, body {
  margin: 0;
  padding: 0;
  height: 100%;
  background: transparent;
}

#editor {
  box-sizing: border-box;
  width: 100%;
  height: 100%;
  padding: 12px 16px;
  border: none;
  outline: none;
  resize: none;
  background: transparent;
  color: #222;
  font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
  font-size: 14px;
  line-height: 1.5;
}
```

### Chirami/Views/NoteWebView.swift

```swift
import AppKit
import WebKit
import SwiftUI
import os

// MARK: - NoteWebView

@MainActor
final class NoteWebView: NSView {
    private let webView: WKWebView
    private let bridge: NoteWebViewBridge
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "NoteWebView")

    private var pendingContent: String?
    private var lastSetContent: String?  // echo-back 防止
    private var isReady: Bool = false

    var onContentChanged: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        let config = WKWebViewConfiguration()
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        let userContentController = WKUserContentController()
        config.userContentController = userContentController

        self.webView = WKWebView(frame: .zero, configuration: config)
        // WKWebView の背景を透過させ SwiftUI の背景を見せる
        self.webView.setValue(false, forKey: "drawsBackground")
        self.webView.underPageBackgroundColor = .clear
        self.bridge = NoteWebViewBridge()
        userContentController.add(bridge, name: "chirami")

        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        webView.wantsLayer = true
        webView.layer?.isOpaque = false
        webView.layer?.backgroundColor = .clear

        bridge.onReady = { [weak self] in self?.handleReady() }
        bridge.onContentChanged = { [weak self] text in
            self?.lastSetContent = text
            self?.onContentChanged?(text)
        }

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        loadEditor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadEditor() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "editor") else {
            logger.error("editor/index.html not found in bundle")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func setContent(_ text: String) {
        guard text != lastSetContent else { return }  // JS 起点の変更を echo-back しない
        if !isReady {
            pendingContent = text
            return
        }
        evalSetContent(text)
    }

    private func handleReady() {
        isReady = true
        if let content = pendingContent {
            pendingContent = nil
            evalSetContent(content)
        }
    }

    private func evalSetContent(_ text: String) {
        let escaped = escapeForJS(text)
        lastSetContent = text
        webView.evaluateJavaScript("window.chirami.setContent(\(escaped));") { [weak self] _, error in
            if let error {
                self?.logger.error("setContent failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func escapeForJS(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode(text),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }
}

// MARK: - NoteWebViewRepresentable

struct NoteWebViewRepresentable: NSViewRepresentable {
    @ObservedObject var model: NoteContentModel

    func makeNSView(context: Context) -> NoteWebView {
        let view = NoteWebView(frame: .zero)
        view.onContentChanged = { [model] text in
            model.text = text
        }
        return view
    }

    func updateNSView(_ nsView: NoteWebView, context: Context) {
        nsView.setContent(model.text)
    }
}
```

### Chirami/Services/NoteWebViewBridge.swift

```swift
import Foundation
import WebKit
import os

// WKScriptMessage は @MainActor (WK_SWIFT_UI_ACTOR) でアノテートされている。
// WebKit はメイン スレッドでデリバリを保証するため assumeIsolated は安全。
@MainActor
final class NoteWebViewBridge: NSObject, WKScriptMessageHandler {
    private let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "NoteWebViewBridge")

    var onReady: (() -> Void)?
    var onContentChanged: ((String) -> Void)?

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }
            switch type {
            case "ready":
                logger.debug("JS ready")
                onReady?()
            case "contentChanged":
                if let text = body["text"] as? String {
                    onContentChanged?(text)
                }
            case "log":
                let level = body["level"] as? String ?? "info"
                let msg = body["message"] as? String ?? ""
                logger.log("[JS \(level, privacy: .public)] \(msg, privacy: .public)")
            default:
                logger.warning("unknown message type: \(type, privacy: .public)")
            }
        }
    }
}
```

### NoteWindow.swift の変更

既存の `LivePreviewEditor` の呼び出しを `NoteWebView` に置き換える。今回は旧実装は削除せず、`NoteContentView` の一箇所だけを差し替える形にする。

差し替えの方針:

- `NoteContentView` で `LivePreviewEditor` を使っていた箇所を `NSViewRepresentable` で `NoteWebView` をラップして置き換える
- `NoteContentModel.text` の更新 → `NoteWebView.setContent` の連携
- `NoteWebView.onContentChanged` → `NoteContentModel.text` の反映 → `NoteStore` 保存（debounce は JS 側で完結しているので Swift 側は即時反映）

### project.yml の変更

変更不要。`sources: path: Chirami` の指定だけで xcodegen が `Chirami/Resources/editor/` 以下の `.html`/`.js`/`.css` を自動的に Copy Bundle Resources フェーズに追加する。

### .mise/tasks/build/editor

```bash
#!/usr/bin/env bash
#MISE description="Build the editor-web JS bundle into Chirami/Resources/editor/"
#MISE sources=["editor-web/src/**/*.ts", "editor-web/src/**/*.css", "editor-web/index.html", "editor-web/package.json"]
#MISE outputs=["Chirami/Resources/editor/bundle.js", "Chirami/Resources/editor/bundle.css", "Chirami/Resources/editor/index.html"]
set -euo pipefail

cd "$(git rev-parse --show-toplevel)/editor-web"

if [ ! -d node_modules ]; then
  npm install
fi

npm run build
```

`mise run build:editor` で実行。`sources`/`outputs` によりソース未変更時はスキップされる。

## 動作確認手順

1. `mise run build:editor` で `Chirami/Resources/editor/` に成果物が生成される
2. `mise run generate` → Xcode でビルド・実行
3. 既存のノートを表示 → `<textarea>` が表示される
4. テキストを入力 → 300ms 後にファイルが更新されていること（`stat` で mtime 確認）
5. 外部エディタでファイルを編集 → ノートウィンドウにも反映されること
6. **キーを 1 回押して離す → クラッシュしないことを確認（最重要）**
7. **連続入力・IME 変換中の入力でもクラッシュしないことを確認**
8. `log stream --predicate 'subsystem == "io.github.uphy.Chirami"'` でブリッジログを確認

## 終了条件

- [x] `<textarea>` でテキスト入力・保存が動作する
- [x] 外部ファイル変更がエディタに反映される
- [x] 1 キー入力後にクラッシュしない
- [x] 連続入力・IME 変換でクラッシュしない
- [x] `os.Logger` に JS からのログが流れている
- [x] 既存の Static Note / Periodic Note / Ad-hoc Note すべてで表示される

## 想定されるリスク

### リスク 1: WKWebView 自体でクラッシュ

**内容**: Phase 1 の時点でクラッシュする場合、前回の調査で除外された「最小 HTML では再現しない」という前提が崩れる。

**対策**:

- Phase 1 で発生した場合は `contenteditable` すら使っていないため、WKWebView の別経路が原因
- `webkit-crash-investigation.md` に追記し、Apple Feedback を再提出
- 本計画を全面的に見直す

### リスク 2: `loadFileURL` の読み取り権限

**内容**: `allowingReadAccessTo` の指定が不適切だと `bundle.js` / `bundle.css` が読めない。

**対策**:

- `url.deletingLastPathComponent()` でエディタディレクトリ全体を許可
- 失敗時はコンソールに `Failed to load resource` が出るので判別可能

### リスク 3: 日本語入力時の contentChanged 多重発火

**内容**: `<textarea>` の `input` イベントは IME 変換中に発火しないはずだが、macOS 26.4 beta で動作が変わっている可能性。

**対策**:

- `compositionstart` / `compositionend` を監視してデバッグログを出力
- 必要なら `isComposing` フラグで `contentChanged` をスキップ

## Phase 2 への引き継ぎ事項

- `NoteWebView` / `NoteWebViewBridge` の基盤は Phase 2 以降もそのまま拡張する
- `<textarea>` の構成は Phase 3 で置き換えるが、Phase 2 の CSS 変数はそのまま流用できるよう `:root` に定義する
- `pendingContent` 方式のキューイングは、Phase 2 で `setTheme` / `setFont` メッセージを追加する際にも流用する
