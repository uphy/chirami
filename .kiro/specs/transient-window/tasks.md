# Implementation Plan

- [ ] 1. Config & Model層の拡張
- [ ] 1.1 NoteConfig に position と auto_hide フィールドを追加する
  - config.yaml のノート設定で `position`（文字列、`"cursor"` または未指定）を受け付けるようにする
  - 同じく `auto_hide`（Boolean、未指定時は nil）を受け付けるようにする
  - CodingKeys に `position` と `auto_hide`（Swift側は `autoHide`）のマッピングを追加する
  - 既存フィールドは変更しない（Optional追加のため後方互換）
  - _Requirements: 3.1, 3.2, 5.1_

- [ ] 1.2 NotePosition enum を定義し、Note struct を拡張する
  - `.fixed` と `.cursor` の2ケースを持つ NotePosition enum を作成する
  - Note struct に `position: NotePosition`（デフォルト `.fixed`）と `autoHide: Bool`（デフォルト `false`）を追加する
  - Equatable の `==` 演算子に新フィールドを含める
  - _Requirements: 3.1, 3.2, 5.1_

- [ ] 1.3 NoteStore の loadFromConfig で新フィールドをマッピングする
  - NoteConfig の `position` 文字列を NotePosition enum に変換する（`"cursor"` → `.cursor`、それ以外・nil → `.fixed`）
  - NoteConfig の `autoHide` を `?? false` でデフォルト値適用する
  - 不正な position 値は `.fixed` にフォールバックする
  - 既存の Combine 購読チェーンでホットリロードが自動的に動作することを確認する
  - _Requirements: 3.3, 3.4, 5.1_

- [ ] 2. カーソル追従ウィンドウ表示
- [ ] 2.1 ホットキー押下時にマウスカーソル位置にウィンドウを表示する
  - show() メソッドに position が `.cursor` の場合の分岐を追加する
  - カーソルモード時、NSEvent.mouseLocation でスクリーン座標を取得しウィンドウの左上座標に設定する
  - NSApp.activate と makeKeyAndOrderFront でキーボードフォーカスを確保する
  - position が `.fixed` の場合は従来の表示動作を維持する
  - _Requirements: 1.1, 1.3_

- [ ] 2.2 画面境界クランプとマルチディスプレイ対応を実装する
  - NSScreen.screens を走査し、NSMouseInRect でカーソルが存在するスクリーンを特定する
  - 該当スクリーンが見つからない場合は NSScreen.main にフォールバックする
  - スクリーンの visibleFrame（メニューバー・Dock除外）に対してウィンドウ全体が収まるよう位置を補正する
  - 左下原点のスクリーン座標系を考慮してクランプ計算を行う
  - _Requirements: 1.2, 1.4_

- [ ] 2.3 cursorモードの状態永続化を制御する
  - windowDidMove での saveWindowState 呼び出しを cursorモード時はスキップする
  - windowDidResize 時は既存の state から position を読み取り、新しい size と合わせて保存する（AppState API 変更不要）
  - position が `.fixed` の場合は従来通り位置・サイズ両方を保存する
  - _Requirements: 4.1, 4.2_

- [ ] 3. 自動非表示とホットリロード対応
- [ ] 3.1 フォーカス離脱時の自動非表示と保存を実装する
  - windowDidResignKey デリゲートメソッドを NoteWindowController に追加する
  - `guard note.autoHide, isVisible` で auto_hide 未設定ノートと既に非表示のウィンドウを除外する
  - 非表示前に NoteContentModel.save() を呼び出してファイルに内容を保存する
  - isVisible チェックにより、ホットキーによる明示的非表示後の二重処理を防止する
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [ ] 3.2 note プロパティを可変にし、ホットリロードで position/autoHide を同期する
  - NoteWindowController の note プロパティを `let` から `var` に変更する
  - applyNoteUpdate() に position と autoHide の同期を追加する
  - config.yaml 変更時に Combine 購読チェーン経由で最新値がコントローラーに反映されることを確認する
  - _Requirements: 3.5_

- [ ] 4. (P) WindowManager統合と互換性確保
- [ ] 4.1 (P) 全体トグルから auto-hide ノートを除外する
  - toggleAllWindows() で auto_hide が true のコントローラーをフィルタリングし、トグル対象から除外する
  - showAllWindows / hideAllWindows / focusAllWindows でも同様に auto-hide ノートを除外する
  - メニューバーのノート一覧表示には影響しない（既存動作維持）
  - _Requirements: 5.2, 5.3_

- [ ] 4.2 (P) transient ノートの起動時非表示を制御する
  - openWindow(for:) で auto_hide かつ position が cursor のノートはコントローラー作成のみ行い、showIfNeeded をスキップする
  - 上記以外のノートは従来通りの起動時表示動作を維持する
  - _Requirements: 4.3, 5.1_
