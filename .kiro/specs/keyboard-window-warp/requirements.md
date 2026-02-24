# Requirements Document

## Project Description (Input)
キーボードで付箋ウィンドウを3x3グリッドの9ポジションにワープさせる機能。HJKLキー+設定可能な修飾キーでグリッド上を移動し、端でサイクルする。

## Introduction

Chirami のユーザーは作業フローを止めずに付箋を操作したい。特にタイル型ウィンドウマネージャ (aerospace 等) 環境や HHKB のようなカーソルキー非搭載キーボードのユーザーにとって、マウスを使わずにキーボードだけで付箋の画面上の位置を素早く変更できることが重要である。本機能は Vim スタイルの HJKL キーで付箋ウィンドウを画面上の 3×3 グリッド（9 ポジション）に移動させる。

## Requirements

### Requirement 1: 3×3グリッドへのワープ

**Objective:** Chirami ユーザーとして、キーボードショートカットで付箋ウィンドウを画面上の 9 つの定位置へ瞬時に移動させたい。マウスを使わず作業フローを維持するため。

#### Acceptance Criteria

1. The Chirami shall divide the visible screen area into a 3×3 grid of 9 positions: top-left, top-center, top-right, middle-left, center, middle-right, bottom-left, bottom-center, bottom-right.
2. When 修飾キー+H を押した場合、the Chirami shall 現在のグリッド位置から左のグリッド位置へ付箋ウィンドウを移動させる。
3. When 修飾キー+L を押した場合、the Chirami shall 現在のグリッド位置から右のグリッド位置へ付箋ウィンドウを移動させる。
4. When 修飾キー+K を押した場合、the Chirami shall 現在のグリッド位置から上のグリッド位置へ付箋ウィンドウを移動させる。
5. When 修飾キー+J を押した場合、the Chirami shall 現在のグリッド位置から下のグリッド位置へ付箋ウィンドウを移動させる。
6. The Chirami shall グリッドポジションへの移動時にアニメーションを付けてウィンドウを滑らかに移動させる。
7. The Chirami shall 各グリッドポジションへ配置する際、画面端から 8pt のマージンを確保する。

### Requirement 2: エッジでのサイクル

**Objective:** Chirami ユーザーとして、グリッドの端で移動キーを押した際に反対側へループしてほしい。方向を変えずに連続操作で全ポジションを巡回するため。

#### Acceptance Criteria

1. When 付箋が左端の列（top-left, middle-left, bottom-left）にあるとき修飾キー+H を押した場合、the Chirami shall 同じ行の右端のポジションへ付箋ウィンドウを移動させる。
2. When 付箋が右端の列（top-right, middle-right, bottom-right）にあるとき修飾キー+L を押した場合、the Chirami shall 同じ行の左端のポジションへ付箋ウィンドウを移動させる。
3. When 付箋が上端の行（top-left, top-center, top-right）にあるとき修飾キー+K を押した場合、the Chirami shall 同じ列の下端のポジションへ付箋ウィンドウを移動させる。
4. When 付箋が下端の行（bottom-left, bottom-center, bottom-right）にあるとき修飾キー+J を押した場合、the Chirami shall 同じ列の上端のポジションへ付箋ウィンドウを移動させる。

### Requirement 3: 現在位置の推定

**Objective:** Chirami ユーザーとして、手動ドラッグで移動した後もキーボードナビゲーションが自然に機能してほしい。状態管理を意識せずに使えるため。

#### Acceptance Criteria

1. When ワープキーを押した場合、the Chirami shall 付箋ウィンドウの中心点を基準に最近傍のグリッドセルを現在位置として推定する。
2. The Chirami shall グリッドポジションの推定に内部状態を使用せず、常にウィンドウの実際の位置から算出する。
3. When 付箋がグリッド境界の中間に位置する場合、the Chirami shall 最近傍のグリッドセルへスナップしてから指定方向へ移動する。

### Requirement 4: 修飾キーの設定

**Objective:** Chirami ユーザーとして、ワープ操作の修飾キーを自分のキーボードやワークフローに合わせてカスタマイズしたい。既存のショートカットとの衝突を避けるため。

#### Acceptance Criteria

1. The Chirami shall `~/.config/chirami/config.yaml` の `warp_modifier` フィールドで修飾キーの組み合わせを設定できるようにする。
2. The Chirami shall `warp_modifier` に `ctrl`, `option`, `command`, `shift` のキーワードを `+` で連結した文字列（例: `"ctrl+option"`）を受け付ける。
3. Where `warp_modifier` が未設定の場合、the Chirami shall `ctrl+option` をデフォルトの修飾キーとして使用する。
4. When `config.yaml` が更新された場合、the Chirami shall アプリ再起動なしに新しい修飾キー設定を反映させる。

### Requirement 5: マルチモニタ対応

**Objective:** Chirami ユーザーとして、マルチモニタ環境でも付箋が現在表示されている画面内で正しくワープしてほしい。

#### Acceptance Criteria

1. When ワープキーを押した場合、the Chirami shall 付箋ウィンドウのフレーム中心点が含まれる画面をワープ基準画面として使用する。
2. The Chirami shall ワープ先の座標計算に対象画面の `visibleFrame`（Dock・メニューバーを除いた領域）を使用する。
3. If 付箋の中心点がいずれの画面にも属さない場合、the Chirami shall メインスクリーンをフォールバックとして使用する。

### Requirement 6: 位置の永続化

**Objective:** Chirami ユーザーとして、ワープ後の位置がアプリ再起動後も保持されてほしい。意図した配置が失われないため。

#### Acceptance Criteria

1. When 付箋ウィンドウがワープした後、the Chirami shall 移動後の位置を `~/.local/state/chirami/state.yaml` に保存する。
2. The Chirami shall ワープによる移動を通常のウィンドウドラッグと同等の位置変更として扱い、既存の状態保存メカニズムを通じて永続化する。
