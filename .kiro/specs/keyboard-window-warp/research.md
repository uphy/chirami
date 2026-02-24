# Research & Design Decisions

---
**Purpose**: Capture discovery findings, architectural investigations, and rationale that inform the technical design.

---

## Summary

- **Feature**: `keyboard-window-warp`
- **Discovery Scope**: Extension（既存システムへの機能追加）
- **Key Findings**:
  - `GlobalHotkeyService.parseKeyString` に `+` 区切りの修飾キー解析ロジックが既存するため、`warpModifierFlags` の実装に完全流用できる
  - `NotePanel.sendEvent` が既にイベント横断ポイントとして確立されており、`keyDown` 処理を同所に追加するのが自然
  - `dragModifier` の設定パターン（`ChiramiConfig` フィールド → computed property → `sendEvent` 参照）をそのまま踏襲できる

## Research Log

### NotePanel.sendEvent の既存処理

- **Context**: キーボードイベントをどこでインターセプトするか検討
- **Sources Consulted**: `Chirami/Views/NotePanel.swift`
- **Findings**:
  - `sendEvent` は `dragModifier` + `leftMouseDown` の処理を担っており、NSPanel 全体のイベントゲートになっている
  - `keyDown` イベントを同所で処理することで、テキストビューに渡る前にワープキーを横取りできる
  - `NotePanel` は `canBecomeKey: true` なので、フォーカス時に `keyDown` を確実に受信する
- **Implications**: `NotePanel.sendEvent` が `keyDown` 処理の実装場所として最適

### 修飾キー解析の既存実装

- **Context**: `warpModifier: "ctrl+option"` のような複合文字列をどう解析するか
- **Sources Consulted**: `Chirami/Services/GlobalHotkeyService.swift`
- **Findings**:
  - `parseKeyString` が `+` 区切りで `NSEvent.ModifierFlags` を組み立てるロジックをすでに持つ
  - `dragModifierFlags` は単一修飾キーのみ対応（switch 文）だが、ワープには複合修飾キーが必要
  - `GlobalHotkeyService` の解析パターンを `ChiramiConfig.warpModifierFlags` に移植する
- **Implications**: 新ライブラリ不要。既存パターンのコピーで解決できる

### 位置推定の設計

- **Context**: 手動ドラッグ後もグリッド移動が機能するための現在位置推定方法
- **Sources Consulted**: `Chirami/Views/NoteWindow.swift` の `clampToScreen`, `showAtCursor`
- **Findings**:
  - NSWindow 座標系は bottom-left 原点
  - `visibleFrame` を使うと Dock・メニューバー除外済みの領域が取得できる
  - ウィンドウ中心点を `visibleFrame` に対する相対位置で正規化し、`round()` で最近傍セルに丸める
- **Implications**: 状態を持たないステートレス推定が可能。`windowDidMove` による既存保存機構と完全に互換

### コールバック方式の選択

- **Context**: `NotePanel` → `NoteWindowController` へのワープ通知手段
- **Sources Consulted**: `Chirami/Views/NoteWindow.swift`, `Chirami/Views/LivePreviewEditor.swift`
- **Findings**:
  - コードベース全体で Delegate ではなく `onXxx` クロージャパターンを採用（`onFontSizeChange`, `onCheckboxClick` 等）
  - `NotePanel` は `NoteWindowController` の `init` で生成されており、クロージャを直接セット可能
- **Implications**: `onWarpKey: ((Character) -> Void)?` クロージャを `NotePanel` に追加するのが一貫したアプローチ

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| sendEvent 拡張 | NotePanel.sendEvent で keyDown をインターセプト | 既存パターンと一致、テキストビューより前に処理 | 修飾キーが完全一致しないと意図しない発火 | 採用。exact match で誤発火防止 |
| NSResponder.keyDown オーバーライド | NSPanel に keyDown を直接実装 | シンプル | nonactivatingPanel では key になりにくいケースがある | 不採用。sendEvent の方が確実 |
| Global Hotkey | HotKey ライブラリでグローバル登録 | 付箋非フォーカス時も動作 | 付箋ごとに4キー×N個 = 大量ホットキー登録が必要 | 不採用。スコープが広すぎる |

## Design Decisions

### Decision: 修飾キーの exact match 判定

- **Context**: `event.modifierFlags.contains(flags)` vs `== flags`（deviceIndependentFlagsMask でマスク後）
- **Alternatives Considered**:
  1. `contains` — 追加修飾キーがあっても発火する
  2. exact match（`.intersection(.deviceIndependentFlagsMask) == warpFlags`）— 指定した修飾キーのみで発火
- **Selected Approach**: exact match
- **Rationale**: テキスト編集中に `ctrl+option+h` 以外のキーコンビネーションとの衝突を防ぐ
- **Trade-offs**: ユーザーが意図せず別の修飾キーを押すと無反応になるが、誤発火よりは良い

### Decision: 位置推定をステートレスに実装

- **Context**: グリッド現在位置を `NoteWindowController` に保持するかどうか
- **Alternatives Considered**:
  1. `currentGridCol/Row: Int` を状態として保持 — 実装シンプルだが手動ドラッグ後に状態がずれる
  2. ウィンドウ位置から動的に推定 — 毎回計算するが常に実際の位置と一致
- **Selected Approach**: ステートレス推定（毎回計算）
- **Rationale**: 手動ドラッグと組み合わせて使うユーザーへの自然な動作を保証する
- **Trade-offs**: 計算コストが増えるが無視できるレベル

## Risks & Mitigations

- テキスト編集中の `ctrl+option+h/j/k/l` 衝突 — exact match 判定で回避。デフォルト `ctrl+option` は標準の macOS ショートカットと衝突しない
- マルチモニタで付箋が画面間にまたがる場合 — ウィンドウ中心点で画面を特定するため、過半数が乗っている画面が基準となり直感的
- `warpModifier` 未設定時のフォールバック — `?? "ctrl+option"` でデフォルト値を保証

## References

- `Chirami/Views/NotePanel.swift` — sendEvent 実装参照
- `Chirami/Config/ConfigModels.swift` — dragModifier パターン参照
- `Chirami/Services/GlobalHotkeyService.swift` — 修飾キー解析パターン参照
- `Chirami/Views/NoteWindow.swift` — 位置・画面操作パターン参照
