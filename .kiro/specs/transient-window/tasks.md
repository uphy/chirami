# Implementation Plan

- [x] 1. Config & Model層の拡張
- [x] 1.1 (P) NoteConfig に position と auto_hide フィールドを追加する
  - config.yaml のノート設定で `position`（文字列、`"cursor"` または未指定）を受け付けるようにする
  - 同じく `auto_hide`（Boolean、未指定時は nil）を受け付けるようにする
  - YAML キーのマッピングを追加する（`auto_hide` → `autoHide`）
  - 既存フィールドは変更しない（Optional追加のため後方互換）
  - _Requirements: 3.1, 3.2, 5.1_

- [x] 1.2 (P) NotePosition enum を定義し、Note struct を拡張する
  - `.fixed` と `.cursor` の2ケースを持つ位置モード enum を作成する
  - Note に `position`（デフォルト `.fixed`）と `autoHide`（デフォルト `false`）を追加する
  - 等値比較に新フィールドを含める
  - _Requirements: 3.1, 3.2, 5.1_

- [x] 1.3 NoteStore の Config→Note 変換で新フィールドをマッピングする
  - config の `position` 文字列を NotePosition に変換する（`"cursor"` → `.cursor`、それ以外 → `.fixed`）
  - `autoHide` を未指定時 `false` でデフォルト適用する
  - 不正な position 値は `.fixed` にフォールバックする
  - 既存の Combine 購読チェーンでホットリロードが自動的に動作することを確認する
  - _Requirements: 3.3, 3.4, 5.1_

- [x] 2. カーソル追従ウィンドウ表示
- [x] 2.1 ホットキー押下時にマウスカーソル位置にウィンドウを表示する
  - show() で position が `.cursor` の場合の分岐を追加する
  - カーソルモード時、マウスカーソルのスクリーン座標を取得しウィンドウの左上座標に設定する
  - キーボードフォーカスを確保するためアプリをアクティベートする
  - position が `.fixed` の場合は従来の表示動作を維持する
  - _Requirements: 1.1, 1.3_

- [x] 2.2 画面境界クランプとマルチディスプレイ対応を実装する
  - カーソルが存在するスクリーンを特定する（該当なしの場合はメインスクリーンにフォールバック）
  - スクリーンの実効領域（メニューバー・Dock除外）に対してウィンドウ全体が収まるよう位置を補正する
  - スクリーン座標系（左下原点）を考慮してクランプ計算を行う
  - _Requirements: 1.2, 1.4_

- [x] 2.3 cursorモードの状態永続化を制御する
  - ウィンドウ移動時の位置保存を cursorモードではスキップする
  - ウィンドウリサイズ時は既存 state から position を読み取り、新しい size と合わせて保存する
  - `.fixed` の場合は従来通り位置・サイズ両方を保存する
  - _Requirements: 4.1, 4.2_

- [x] 3. 自動非表示とホットリロード対応
- [x] 3.1 フォーカス離脱時の自動非表示と保存を実装する
  - ウィンドウのキーステータス喪失時のデリゲートハンドラを追加する
  - `autoHide` 未設定ノートと既に非表示のウィンドウは処理をスキップする
  - 非表示前にノートの内容をファイルに保存する
  - isVisible チェックにより、ホットキーによる明示的非表示後の二重処理を防止する
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 3.2 ホットリロードで position/autoHide を同期する
  - note プロパティを可変にする
  - 既存の更新ハンドラに position と autoHide の同期を追加する
  - config.yaml 変更時に最新値がコントローラーに反映されることを確認する
  - _Requirements: 3.5_

- [x] 4. WindowManager統合と互換性確保
- [x] 4.1 全体トグルから auto-hide ノートを除外する
  - 全体表示切り替え、全体表示、全体非表示、全体フォーカスの各操作で autoHide ノートを対象から除外する
  - メニューバーのノート一覧表示には影響しない（既存動作維持）
  - _Requirements: 5.2, 5.3_

- [x] 4.2 transient ノートの起動時非表示を制御する
  - autoHide かつ cursor のノートはウィンドウ作成のみ行い、表示をスキップする
  - 上記以外のノートは従来通りの起動時表示動作を維持する
  - _Requirements: 4.3, 5.1_
