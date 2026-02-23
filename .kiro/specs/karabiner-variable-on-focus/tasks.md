# Implementation Plan

- [x] 1. 設定モデルの拡張
  - `KarabinerConfig` 構造体を定義し、変数名 (`variable`)、フォーカス時の値 (`onFocus`)、フォーカス解除時の値 (`onUnfocus`) を保持する
  - `CodingKeys` で `on_focus` → `onFocus`、`on_unfocus` → `onUnfocus` の snake_case マッピングを行う
  - `FusenConfig` にオプショナルな `karabiner` プロパティを追加する
  - `karabiner` セクションが config.yaml に存在しない場合、`nil` としてデコードされることを確認する
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 2. KarabinerService の実装
- [x] 2.1 karabiner_cli 実行ロジックの実装
  - `karabiner_cli` のパス (`/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli`) の存在を `FileManager` でチェックし、存在しない場合はログ出力のみでスキップする
  - Foundation `Process` で `--set-variables '{"変数名": 値}'` コマンドを `Task.detached` でバックグラウンド実行する
  - 終了コードが 0 以外の場合、標準エラー出力をログに記録し、アプリの動作は継続する
  - `lastSetValue` を保持し、同じ値の再設定をスキップする
  - _Requirements: 3.1, 3.2_

- [x] 2.2 フォーカス監視と状態集約の実装
  - NotificationCenter で `NSWindow.didBecomeKeyNotification` / `didResignKeyNotification` を監視する
  - 通知元が `NotePanel` であることをフィルタリングする
  - `focusedPanelCount` で全 NotePanel のフォーカス状態を集約し、0→1 でフォーカス、1→0 でフォーカス解除と判定する
  - unfocus 判定に `DispatchWorkItem` + `DispatchQueue.main.async` で 1 RunLoop の遅延を入れ、直後の becomeKey 通知でキャンセルすることで、ウィンドウ間遷移時の冗長な CLI 呼び出しを抑制する
  - `config.karabiner` が `nil` の場合は CLI 実行をスキップする
  - _Requirements: 1.1, 1.2, 2.4_

- [x] 2.3 AppDelegate への統合
  - `AppDelegate` に `KarabinerService` のインスタンスを保持し、`applicationDidFinishLaunching` で `startObserving()` を呼び出す
  - config.yaml に karabiner セクションを追加し、フォーカス/フォーカス解除で `karabiner_cli` が正しく呼び出されることを手動で確認する
  - _Requirements: 1.1, 1.2_
