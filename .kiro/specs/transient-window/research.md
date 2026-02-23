# Research & Design Decisions: transient-window

## Summary

- **Feature**: `transient-window`
- **Discovery Scope**: Extension
- **Key Findings**:
  - `NSEvent.mouseLocation` はグローバルホットキーコールバック内で正確に動作する（呼び出し時点のマウス位置を返す）
  - `NSPanel` + `.nonactivatingPanel` + `canBecomeKey = true` の組み合わせで `windowDidResignKey` は期待通り発火する
  - macOSの座標系は左下原点であり、`NSScreen.visibleFrame` を使用して画面境界クランプを行う

## Research Log

### NSEvent.mouseLocation のグローバルホットキーコールバック内精度

- **Context**: Gap Analysisで、HotKeyライブラリのコールバック時点でのマウス位置が正確かどうか要調査とされた
- **Sources Consulted**:
  - [Apple Developer - mouseLocation](https://developer.apple.com/documentation/appkit/nsevent/1533380-mouselocation)
  - [Swift Forums - mouse position detection](https://forums.swift.org/t/is-there-a-way-to-detect-and-get-local-coordinates-of-mouse-position-location-in-swiftui/46904)
- **Findings**:
  - `NSEvent.mouseLocation` はクラスプロパティで、いつでも呼び出し可能（イベントオブジェクト不要）
  - コールバック呼び出し時点の「現在の」マウス位置を返す（イベント発火時点ではない）
  - ホットキー→toggle→show はMainThread上で同期的に実行されるため、実質的な遅延は無視可能
  - 座標はスクリーン座標系（左下原点）で返される
- **Implications**: `NoteWindowController` の `show` 処理内で `NSEvent.mouseLocation` を呼び出すだけで十分。特別なタイミング制御は不要

### NSPanel の windowDidResignKey 発火挙動

- **Context**: `.nonactivatingPanel` スタイルの `NSPanel` で `windowDidResignKey` が期待通りに動作するか要確認
- **Sources Consulted**:
  - [Apple Developer - NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
  - [Apple Developer - becomesKeyOnlyIfNeeded](https://developer.apple.com/documentation/appkit/nspanel/1528836-becomeskeyonlyifneeded)
  - [Cindori - Make a floating panel in SwiftUI](https://cindori.com/developer/floating-panel)
  - [philz.blog - NSPanel's Nonactivating Style Mask](https://philz.blog/nspanel-nonactivating-style-mask-flag/)
- **Findings**:
  - `canBecomeKey = true` をオーバーライドした `NSPanel` は key window になれるため、`windowDidResignKey` は正常に発火する
  - 既存の `NotePanel` は既に `canBecomeKey = true` と `.nonactivatingPanel` を設定済み
  - Spotlight/Alfred型のパネル実装でも `resignMain()` や `windowDidResignKey` でフォーカス離脱を検知するパターンが一般的
  - `.nonactivatingPanel` のスタイルマスクを初期化後に変更するとバグが発生する（FB16484811）が、既存コードは初期化時に設定しているため影響なし
  - `becomesKeyOnlyIfNeeded` はデフォルト `false`。`NotePanel` はこれを変更していないため、`makeKeyAndOrderFront` で確実にkey windowになる
- **Implications**: 既存の `NotePanel` サブクラスに `windowDidResignKey` デリゲートメソッドを追加するだけでauto-hide機能を実現可能。追加のスタイル設定変更は不要

### マルチディスプレイでの画面境界検出

- **Context**: カーソル位置にウィンドウを表示する際、正しいディスプレイの範囲内にクランプする必要がある
- **Sources Consulted**:
  - [Apple Developer - NSScreen](https://developer.apple.com/documentation/appkit/nsscreen)
- **Findings**:
  - `NSScreen.screens` で接続中の全ディスプレイを取得
  - `NSMouseInRect(mouseLocation, screen.frame, false)` でカーソルが存在するスクリーンを特定
  - `screen.visibleFrame` はメニューバーとDockを除いた利用可能領域を返す
  - フォールバックとして `NSScreen.main` を使用
- **Implications**: ウィンドウ位置の画面クランプロジックに `visibleFrame` を使用し、メニューバー・Dock領域への配置を防止する

## Design Decisions

### Decision: NotePosition の型表現

- **Context**: config.yamlの `position` フィールドの値をSwiftコードでどう表現するか
- **Alternatives Considered**:
  1. `String?` をそのまま使用（"cursor" / nil）
  2. `enum NotePosition` を導入（`.fixed` / `.cursor`）
- **Selected Approach**: `enum NotePosition` を `Note` モデルに導入。`NoteConfig` は `String?` のままとし、マッピング時にenumに変換
- **Rationale**: Swift の型安全性を活用し、switch文での網羅性チェックが可能。将来的に他の位置モードを追加する際にも拡張しやすい
- **Trade-offs**: NoteConfig（Codable）は文字列のまま保持するため、マッピング層が必要だが、既存の `loadFromConfig()` に自然に組み込める

### Decision: Auto-hide とホットキートグルの競合回避

- **Context**: ホットキーで非表示にした際、`windowDidResignKey` が追加で発火する可能性がある
- **Alternatives Considered**:
  1. `isHotkeyToggling` フラグを導入
  2. `windowDidResignKey` 内で `isVisible` を確認
  3. `DispatchQueue.main.async` で遅延処理
- **Selected Approach**: `windowDidResignKey` 内で `isVisible` を確認し、既に非表示なら何もしない
- **Rationale**: `orderOut(nil)` 実行後、`isVisible` は `false` を返す。`windowDidResignKey` がその後に発火しても、`isVisible` チェックで二重非表示を防止できる。フラグ管理より状態ベースの判定の方がシンプルで堅牢
- **Trade-offs**: `orderOut` と `windowDidResignKey` の発火順序がAppKitの実装に依存するが、`isVisible` の確認はどの順序でも安全に動作する

### Decision: Transient Window の起動時挙動

- **Context**: `auto_hide: true` + `position: cursor` のノートをアプリ起動時にどう扱うか
- **Selected Approach**: `WindowManager.openWindow(for:)` で `note.autoHide && note.position == .cursor` の場合、ウィンドウを作成するが表示しない（`showIfNeeded` をスキップ）
- **Rationale**: Transient Window はホットキー起動が前提。起動時に表示する意味がなく、カーソル位置も不定

## Risks & Mitigations

- `windowDidResignKey` の発火タイミング — `isVisible` チェックで二重処理を防止。万が一の保険として `save()` は冪等性を維持
- マルチディスプレイでの座標変換 — `NSScreen.screens` と `visibleFrame` を使用し、Retinaスケーリングは `NSScreen` が自動処理
- HotKeyライブラリのコールバック遅延 — MainThread同期実行のため無視可能。ユーザー体感で問題なし

## References

- [Apple Developer - NSEvent.mouseLocation](https://developer.apple.com/documentation/appkit/nsevent/1533380-mouselocation)
- [Apple Developer - NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [Apple Developer - becomesKeyOnlyIfNeeded](https://developer.apple.com/documentation/appkit/nspanel/1528836-becomeskeyonlyifneeded)
- [Cindori - Floating Panel in SwiftUI](https://cindori.com/developer/floating-panel)
- [philz.blog - NSPanel's Nonactivating Style Mask](https://philz.blog/nspanel-nonactivating-style-mask-flag/)
- [Markus Bodner - Spotlight-like Window](https://www.markusbodner.com/til/2021/02/08/create-a-spotlight/alfred-like-window-on-macos-with-swiftui/)
