# Phase 2: テーマ・フォント統合

## 目的

`config.yaml` のカスタム `color_schemes` とフォント設定を WebView に反映する。CSS 変数注入の仕組みを確立し、Phase 3 以降の CodeMirror でもそのまま使えるようにする。

**重要**: Phase 1 の `<textarea>` 構成を維持したまま実施する。Phase 3 で CodeMirror に置き換わっても、同じ CSS 変数名・同じ注入 API を使う設計にする。

## スコープ

### 含む

- Swift 側: `ColorScheme` → CSS 変数文字列の変換ユーティリティ
- JS 側: `setTheme(cssVars)` / `setFont(family, size)` API の追加
- ダークモード検知と再注入
- `config.yaml` 再読込時の再注入
- `<textarea>` にテーマ・フォントを適用
- フォント名の macOS 内部フォント対応（`.` 始まりの内部名のハンドリング）

### 含まない

- Markdown のシンタックスハイライト（Phase 3・4）
- フォントサイズ変更ショートカット（Phase 5）
- CodeMirror 固有のスタイル（Phase 3 以降）

## タスク一覧

- [x] `Chirami/Services/ColorSchemeCSSConverter.swift` 作成
- [x] `editor-web/src/theme.ts` 作成
- [x] `editor-web/src/bridge.ts` に `setTheme` / `setFont` API を追加
- [x] `editor-web/src/main.ts` で API を接続
- [x] `editor-web/src/style.css` に CSS 変数定義を追加
- [x] `NoteWebView.swift` に `setTheme` / `setFont` メソッド追加
- [x] `NoteWebView.swift` でダークモード変更を監視（`NSAppearance.bestMatch`）
- [x] `NoteWindow.swift` / `NoteContentView` から `setTheme` / `setFont` を呼ぶ
- [x] `config.yaml` 再読込フローとの接続
- [x] フォント名変換のフォールバック実装（ログ警告含む）
- [x] 実機確認: プリセットテーマ（yellow, blue, green, pink, purple, gray）すべて反映
- [x] 実機確認: カスタム `color_schemes` が反映
- [x] 実機確認: ダーク↔ライト切り替えで色が変わる

## 実装詳細

### CSS 変数設計

```css
:root {
  --chirami-bg: rgb(255, 245, 183);
  --chirami-text: rgb(115, 97, 26);
  --chirami-link: rgb(46, 83, 143);
  --chirami-code: rgb(107, 61, 28);
  --chirami-code-bg: rgba(0, 0, 0, 0.07);
  --chirami-selection: rgba(115, 97, 26, 0.15);
  --chirami-font: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
  --chirami-font-size: 14px;
}

html, body {
  margin: 0;
  padding: 0;
  height: 100%;
  background: var(--chirami-bg);
  color: var(--chirami-text);
  font-family: var(--chirami-font);
  font-size: var(--chirami-font-size);
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
  color: inherit;
  font-family: inherit;
  font-size: inherit;
  line-height: 1.5;
  -webkit-font-smoothing: antialiased;
}

#editor::selection {
  background-color: var(--chirami-selection);
}
```

変数名は Phase 3 以降の CodeMirror でもそのまま使う。Phase 3 では `.cm-editor` 等にこの変数を適用する。

### Swift: ColorSchemeCSSConverter

```swift
import AppKit

enum ColorSchemeCSSConverter {
    static func cssVariables(for scheme: ColorScheme, isDark: Bool) -> String {
        let c = isDark ? scheme.dark : scheme.light
        let codeBg = isDark ? "rgba(255, 255, 255, 0.08)" : "rgba(0, 0, 0, 0.07)"
        let selectionAlpha = isDark ? 0.3 : 0.15

        return """
        --chirami-bg: \(rgb(c.background));
        --chirami-text: \(rgb(c.text));
        --chirami-link: \(rgb(c.link));
        --chirami-code: \(rgb(c.code));
        --chirami-code-bg: \(codeBg);
        --chirami-selection: \(rgba(c.text, alpha: selectionAlpha));
        """
    }

    private static func rgb(_ components: [Double]) -> String {
        guard components.count >= 3 else { return "rgb(0, 0, 0)" }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return "rgb(\(r), \(g), \(b))"
    }

    private static func rgba(_ components: [Double], alpha: Double) -> String {
        guard components.count >= 3 else { return "rgba(0, 0, 0, \(alpha))" }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return "rgba(\(r), \(g), \(b), \(alpha))"
    }
}
```

### Swift: フォント名の CSS 変換

```swift
enum FontCSSConverter {
    private static let logger = Logger(subsystem: "io.github.uphy.Chirami", category: "FontCSSConverter")
    private static let fallback = "-apple-system, BlinkMacSystemFont, \"Helvetica Neue\", sans-serif"

    static func cssFontFamily(from name: String?) -> String {
        guard let name, !name.isEmpty else { return fallback }
        // macOS 内部フォント名は CSS で直接使えない
        if name.hasPrefix(".") { return fallback }
        if NSFont(name: name, size: 14) == nil {
            logger.warning("font not found, fallback to system: \(name, privacy: .public)")
            return fallback
        }
        // CSS font-family に安全にクォートして渡す
        return "\"\(name)\", " + fallback
    }
}
```

### JS: editor-web/src/theme.ts

```ts
export function applyCSSVariables(cssVars: string) {
  // 既存の <style id="chirami-theme"> を置き換える
  let styleEl = document.getElementById("chirami-theme") as HTMLStyleElement | null;
  if (!styleEl) {
    styleEl = document.createElement("style");
    styleEl.id = "chirami-theme";
    document.head.appendChild(styleEl);
  }
  styleEl.textContent = `:root {\n${cssVars}\n}`;
}

export function applyFont(family: string, size: number) {
  // CSS 変数として設定
  document.documentElement.style.setProperty("--chirami-font", family);
  document.documentElement.style.setProperty("--chirami-font-size", `${size}px`);
}
```

### JS: bridge.ts の追加

```ts
type SwiftToJsApi = {
  setContent: (text: string) => void;
  setTheme: (cssVars: string) => void;
  setFont: (family: string, size: number) => void;
};
```

### JS: main.ts の追加

```ts
import { applyCSSVariables, applyFont } from "./theme";

exposeApi({
  setContent: (text: string) => { /* Phase 1 と同じ */ },
  setTheme: (cssVars: string) => applyCSSVariables(cssVars),
  setFont: (family: string, size: number) => applyFont(family, size),
});
```

### Swift: NoteWebView のメソッド追加

```swift
extension NoteWebView {
    func setTheme(_ scheme: ColorScheme, isDark: Bool) {
        let cssVars = ColorSchemeCSSConverter.cssVariables(for: scheme, isDark: isDark)
        enqueueOrEval("window.chirami.setTheme(\(jsonString(cssVars)));")
    }

    func setFont(name: String?, size: Double) {
        let family = FontCSSConverter.cssFontFamily(from: name)
        enqueueOrEval("window.chirami.setFont(\(jsonString(family)), \(size));")
    }

    private func enqueueOrEval(_ script: String) {
        if !isReady {
            pendingScripts.append(script)
            return
        }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}
```

`handleReady()` で `pendingScripts` を順番に実行する。`setContent` も同じキューに統合しても良い。

### ダークモード検知

```swift
// NoteWebView 内
private var appearanceObservation: NSKeyValueObservation?

override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    notifyAppearanceChange()
}

private func notifyAppearanceChange() {
    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    onAppearanceChanged?(isDark)
}

var onAppearanceChanged: ((Bool) -> Void)?
```

`NoteWindowController` 側で `onAppearanceChanged` を受け、現在のノートの `ColorScheme` を解決して `setTheme` を呼ぶ。

### config.yaml 再読込との接続

既存の config 再読込フロー（`AppConfig.shared` が変更を検知してノートを更新する箇所）で、`NoteWindowController` が `NoteWebView.setTheme` / `setFont` を再度呼び出すようにする。

## 動作確認手順

1. `config.yaml` で各プリセットテーマを割り当てたノートを作成
2. 各ノートを開き、背景・テキスト色が期待通りになっていること
3. カスタム `color_schemes` を定義し、割り当てたノートで反映されること
4. macOS のダークモードを切り替え → 色が追従すること
5. フォント設定を変更 → 再読込後に反映されること
6. `config.yaml` の `font` に存在しないフォント名を書く → フォールバックして警告ログが出ること
7. `.AppleSystemUIFont` のような内部名を書く → フォールバックすること
8. **キー入力時・テーマ切り替え時にクラッシュしないこと**

## 終了条件

- [ ] すべてのプリセットテーマが反映される
- [ ] カスタム `color_schemes` が反映される
- [ ] ダーク↔ライト切り替えで色が追従する
- [ ] フォント名変換のフォールバックが動作する
- [ ] `config.yaml` 再読込で新しいテーマが反映される
- [ ] テーマ切り替え時にクラッシュしない

## 想定されるリスク

### リスク 1: CSS 変数注入の多重化

**内容**: `setTheme` を連続で呼ぶと複数の `<style>` タグが生成されて競合する可能性。

**対策**:

- `theme.ts` で `id="chirami-theme"` の要素を置き換える方式にする（上の実装参照）

### リスク 2: ダークモード検知のタイミングずれ

**内容**: `viewDidChangeEffectiveAppearance` と `NSApp.effectiveAppearance` の値が一時的にずれる。

**対策**:

- `effectiveAppearance.bestMatch` を使って現在のビューの appearance を確実に取得
- `Task { @MainActor in ... }` でメインアクター上で実行

### リスク 3: 色成分の範囲外

**内容**: `config.yaml` に `[2.0, -0.1, 0.5]` のような範囲外の値が入っていると CSS が壊れる可能性。

**対策**:

- Swift 側で `max(0, min(1, component))` でクランプしてから `* 255`
- 既存の `ColorScheme` パーサーでバリデーションが入っているか確認（なければ追加）

## Phase 3 への引き継ぎ事項

- CSS 変数名（`--chirami-bg` 等）は Phase 3 でも同じ名前を使う
- `setTheme` / `setFont` API は CodeMirror に切り替えても同じシグネチャで動く
- ダークモード再注入のフローはそのまま流用
- `pendingScripts` キューの仕組みは Phase 3 以降の API 追加でも流用する
