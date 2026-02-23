# Implementation Plan

- [x] 1. Option+ドラッグによるウィンドウ移動
- [x] 1.1 mouseDown に Option キー判定を追加し performDrag でウィンドウ移動を開始する
  - Option キーの押下状態を管理する `isOptionHeld` フラグを追加する
  - `mouseDown(with:)` の冒頭で Option キーの有無をチェックし、押されていれば `performDrag` でウィンドウ移動を開始して早期 return する
  - Option キーなしの場合は既存のチェックボックス・リンク・テキスト選択処理がそのまま動作することを確認する
  - ウィンドウ移動完了後に `windowDidMove` 経由で位置が永続化されることを確認する (既存ロジック、変更不要)
  - `.cursor` モードのウィンドウで移動後に位置が永続化されないことを確認する (既存ロジック、変更不要)
  - _Requirements: 1.1, 1.2, 1.3, 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 2. カーソルフィードバックの実装
- [x] 2.1 flagsChanged と mouseMoved で Option キー状態に応じたカーソル切り替えを実装する
  - `flagsChanged(with:)` を override し、Option 押下時に `openHand` カーソルを push、解放時に pop する。`isOptionHeld` フラグで二重 push を防止する
  - `mouseMoved(with:)` の冒頭で Option キーチェックを追加し、押下中は `openHand` カーソルを表示して既存のチェックボックス/リンクカーソル処理をスキップする
  - _Requirements: 2.1, 2.3_

- [x] 2.2 performDrag 前後のカーソル管理を明示的リセット方式で実装する
  - `performDrag` 呼び出し前: openHand が push 済みなら pop し、closedHand を push する
  - `performDrag` 完了後: closedHand を pop し、現在の `modifierFlags` で Option 状態を再評価する。Option が押されていれば openHand を再 push、そうでなければ `isOptionHeld = false` でクリーンな状態に戻す
  - _Requirements: 2.2, 2.3_
