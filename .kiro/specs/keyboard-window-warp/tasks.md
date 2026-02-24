# Implementation Plan

- [x] 1. `ChiramiConfig` に `warp_modifier` 設定サポートを追加する
  - `warpModifier: String?` フィールドを追加し、YAML キー `warp_modifier` にマッピングする
  - `warpModifierFlags` computed property を実装し、`+` 区切りの修飾キー文字列（`ctrl/control`, `option/opt`, `command/cmd`, `shift`）を `NSEvent.ModifierFlags` に変換する
  - 未設定時は `"ctrl+option"` をデフォルトとし、未知のキーワードは無視して残りのフラグで動作する
  - `dragModifier` フィールドの隣に配置してパターンを統一する
  - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [x] 2. `NotePanel` でワープキーをインターセプトする
  - `onWarpKey: ((Character) -> Void)?` クロージャプロパティを追加する
  - `sendEvent` の既存 `dragModifier` 処理ブロックの後に `keyDown` 処理を追加する
  - `modifierFlags` と `warpModifierFlags` の exact match 判定（`deviceIndependentFlagsMask` でマスク後に `==` 比較）を実装する
  - 修飾キーが一致し HJKL のいずれかである場合のみ `onWarpKey` を呼び出して `return` し、テキストビューへの伝播を遮断する
  - それ以外のキー入力は `super.sendEvent` に渡す
  - _Requirements: 1.2, 1.3, 1.4, 1.5, 4.1, 4.2, 4.3, 4.4_

- [x] 3. `NoteWindowController` にグリッドワープロジックを実装する

- [x] 3.1 基準画面の特定とグリッド位置推定を実装する
  - ウィンドウフレームの中心点が含まれる `NSScreen` を返す画面特定メソッドを実装する（該当なしは `NSScreen.main` にフォールバック）
  - ウィンドウ中心座標と `visibleFrame` から最近傍グリッドセル（col: 0–2, row: 0–2）を返す位置推定メソッドを実装する（NSWindow は bottom-left 原点のため row=0 が下端）
  - 推定式: `col = clamp(round((center.x - frame.minX) / (frame.width / 2)), 0, 2)`、row も同様
  - 内部状態を持たずウィンドウの実際の位置から毎回算出するステートレス設計にする
  - _Requirements: 3.1, 3.2, 3.3, 5.1, 5.2, 5.3_

- [x] 3.2 グリッド移動計算とワープ先座標算出を実装する
  - HJKL キーに対するモジュロ演算でサイクル移動を実装する（H: `(col+2)%3`、L: `(col+1)%3`、K: `(row+1)%3`、J: `(row+2)%3`）
  - グリッド座標（col, row）・ウィンドウサイズ・`visibleFrame` からウィンドウ origin を返す計算メソッドを実装する
  - マージン定数 8pt を適用する（col=0: `minX+8`、col=1: `midX-w/2`、col=2: `maxX-w-8`、row も同様）
  - _Requirements: 1.1, 1.7, 2.1, 2.2, 2.3, 2.4_

- [x] 3.3 ワープ実行と既存システムへの統合を行う
  - `warpTo(key:)` メソッドを実装し、画面取得 → 位置推定 → 移動適用 → 座標計算 → アニメーション実行の一連の流れをまとめる
  - アニメーションは `setFrame(_:display:animate:true)` で実装する
  - `NoteWindowController.init` 内で `onWarpKey` クロージャをセットし NotePanel と接続する
  - `windowDidMove` による既存の `saveWindowState()` でワープ後の位置が自動保存されることを確認する
  - _Requirements: 1.2, 1.3, 1.4, 1.5, 1.6, 6.1, 6.2_

- [ ]* 4.1 (P) グリッド計算ロジックのユニットテストを作成する
  - `inferGridPosition` について画面の各ゾーン（端・中央・グリッド境界付近）でグリッド座標推定が正確であることを検証する
  - `applyMove` について HJKL 4方向 × 9ポジション = 36 ケースのサイクル移動（端ラップを含む）を網羅的にテストする
  - `gridOrigin` について 9 ポジション各々の origin 座標と 8pt マージンの適用を検証する
  - _Requirements: 1.1, 1.7, 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3_

- [ ]* 4.2 (P) 修飾キー設定解析のユニットテストを作成する
  - `warpModifierFlags` について単一修飾キー・複合修飾キー・未知キーワードを含む文字列の解析結果を検証する
  - `warp_modifier` 未設定時のデフォルト値（`ctrl+option`）適用を確認する
  - _Requirements: 4.2, 4.3_
