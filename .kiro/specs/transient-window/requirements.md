# Requirements Document

## Introduction

Transient Window (揮発性ウィンドウ) は、「書く」という一瞬のアクションに特化した機能である。グローバルホットキーでマウスカーソル位置にノートウィンドウをポップアップさせ、フォーカスが外れたら自動で非表示にすることで、作業中のコンテキスト移動をゼロにする。

既存のFusenアプリはノートごとのホットキーによるウィンドウ表示切り替え、state.yamlでのウィンドウ位置永続化を備えている。本機能は、NoteConfigに `position` と `auto_hide` の2つの設定項目を追加し、既存のウィンドウ管理・ホットキー基盤を拡張する形で実現する。

## Requirements

### Requirement 1: カーソル追従ウィンドウ表示

**Objective:** ユーザーとして、ノートウィンドウをマウスカーソルの位置にポップアップさせたい。作業中の視線移動を最小限にし、すぐにメモを書き始められるようにするため。

#### Acceptance Criteria

1. When ユーザーが `position: cursor` が設定されたノートのホットキーを押下する, the Fusen shall マウスカーソルの現在位置を基準にノートウィンドウを表示する
2. The Fusen shall カーソル位置にウィンドウを表示する際、ウィンドウ全体が画面内に収まるように位置を補正する
3. When `position: cursor` が設定されたノートのホットキーが押下される, the Fusen shall ウィンドウの左上座標をマウスカーソル位置に設定する（画面端補正が不要な場合）
4. When 複数ディスプレイ環境でカーソルが任意のディスプレイ上にある, the Fusen shall カーソルが存在するディスプレイの範囲内にウィンドウを表示する

### Requirement 2: 自動非表示（Auto Hide）

**Objective:** ユーザーとして、メモを書き終えた後にウィンドウを手動で閉じる操作を省略したい。フォーカスが外れたら自動的にウィンドウが隠れることで、ワークフローへの復帰をシームレスにするため。

#### Acceptance Criteria

1. When `auto_hide: true` が設定されたノートウィンドウからフォーカスが外れる, the Fusen shall そのウィンドウを自動的に非表示（Visible: false）にする
2. When `auto_hide: true` のノートウィンドウが非表示になる, the Fusen shall ノートの内容をファイルに保存する
3. While `auto_hide` が未設定または `false` のノートに対して, the Fusen shall 従来通りフォーカス離脱で非表示にしない（既存動作を維持する）
4. When `auto_hide: true` のウィンドウがキーボードショートカットでトグルされる, the Fusen shall ホットキーによる明示的な非表示操作を自動非表示より優先する

### Requirement 3: 設定ファイル拡張

**Objective:** ユーザーとして、config.yamlのノート設定に `position` と `auto_hide` を追加し、宣言的にTransient Window挙動を制御したい。既存の設定体系と一貫性を保つため。

#### Acceptance Criteria

1. The Fusen shall config.yamlの `notes` 配列内の各ノート設定で `position` フィールドを受け付ける（値: `cursor` または未指定）
2. The Fusen shall config.yamlの `notes` 配列内の各ノート設定で `auto_hide` フィールド（Boolean）を受け付ける
3. When `position` フィールドが未指定の場合, the Fusen shall 従来通りstate.yamlに保存された固定位置にウィンドウを表示する
4. When `auto_hide` フィールドが未指定の場合, the Fusen shall デフォルト値 `false` として従来動作を維持する
5. When config.yamlが変更される, the Fusen shall `position` と `auto_hide` の変更をホットリロードで反映する

### Requirement 4: Transient Windowの状態管理

**Objective:** ユーザーとして、Transient Windowの揮発的な性質に合った状態管理を行いたい。カーソル追従ウィンドウの位置はセッション毎に変わるため、不要な永続化を避けるため。

#### Acceptance Criteria

1. While `position: cursor` が設定されたノートの場合, the Fusen shall ウィンドウ位置をstate.yamlに永続化しない
2. The Fusen shall `position: cursor` が設定されたノートのウィンドウサイズはstate.yamlに永続化する
3. When アプリケーションが起動する, the Fusen shall `auto_hide: true` かつ `position: cursor` のノートをデフォルトで非表示状態で起動する

### Requirement 5: 既存機能との互換性

**Objective:** ユーザーとして、Transient Window機能の追加により既存のノートウィンドウの動作が変わらないことを保証したい。既存のワークフローを壊さないため。

#### Acceptance Criteria

1. The Fusen shall `position` および `auto_hide` が未設定のノートに対して、従来と同一の動作を維持する
2. When アプリ全体のホットキー（`hotkey`設定）が押下される, the Fusen shall `auto_hide: true` のノートを全体トグル対象から除外する
3. While メニューバーのノート一覧にTransient Window設定のノートが含まれる場合, the Fusen shall 他のノートと同様にリストに表示し、手動での表示切り替えを許可する
