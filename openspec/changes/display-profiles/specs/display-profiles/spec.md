## ADDED Requirements

### Requirement: Profile definition in config.yaml

config.yaml の `display.profiles` セクションで Ad-hoc Note の名前付き設定プリセット（profile）を定義できる。各 profile は title, color, transparency, fontSize, position, hotkey を持つ。すべてのフィールドはオプショナルで、未指定時はハードコードデフォルトで解決される。

#### Scenario: Profile with all fields specified

- **WHEN** config.yaml に以下の profile が定義されている:
  ```yaml
  display:
    profiles:
      notify:
        title: Notification
        color: pink
        transparency: 0.85
        font_size: 13
        position: cursor
        hotkey: cmd+shift+n
  ```
- **THEN** `notify` profile の全設定が定義通りに解決される

#### Scenario: Profile with partial fields falls back to hardcoded defaults

- **WHEN** config.yaml に以下が定義されている:
  ```yaml
  display:
    profiles:
      agent:
        color: blue
  ```
- **THEN** agent profile の color は `blue`（profile で指定）、その他はハードコードデフォルト（transparency: 0.9, fontSize: 14, position: fixed）

#### Scenario: No display section

- **WHEN** config.yaml に `display` セクションが存在しない
- **THEN** アプリは正常に起動し、既存機能に影響しない

#### Scenario: Registered Note and Ad-hoc Note share hardcoded defaults

- **WHEN** Registered Note に color が未指定
- **AND** Ad-hoc Note の profile にも color が未指定
- **THEN** 両方のウィンドウがハードコードデフォルトの `yellow` で表示される

### Requirement: CLI --profile flag

`chirami display` コマンドに `--profile <name>` フラグを追加する。指定された profile 名を URI パラメータ `profile=<name>` として渡す。

#### Scenario: Display with profile

- **WHEN** `chirami display --profile notify "Build done!"` を実行
- **THEN** URI `chirami://display?profile=notify&content=Build%20done!` が生成され、notify profile の設定で Ad-hoc Note が表示される

#### Scenario: Display without profile

- **WHEN** `chirami display "Hello"` を実行（--profile 省略）
- **THEN** URI に `profile` パラメータは含まれず、ハードコードデフォルトの設定で Ad-hoc Note が表示される

#### Scenario: Unknown profile name

- **WHEN** `chirami display --profile nonexistent "Hello"` を実行し、config.yaml の `display.profiles` に `nonexistent` が存在しない
- **THEN** ハードコードデフォルトの設定で Ad-hoc Note が表示される（エラーにはしない）

### Requirement: Profile settings applied to Ad-hoc Note window

`DisplayWindowManager` は URI の `profile` パラメータから profile 設定を解決し、Ad-hoc Note ウィンドウに適用する。適用対象: ウィンドウカラー、透過度、フォントサイズ、タイトル、位置（cursor/fixed）。

#### Scenario: Color and title applied

- **WHEN** profile `notify` の color が `pink`、title が `Notification` と定義されている
- **THEN** 表示される Ad-hoc Note の背景色が pink になり、タイトルバーに `Notification` と表示される

#### Scenario: Position cursor

- **WHEN** profile `notify` の position が `cursor` と定義されている
- **THEN** Ad-hoc Note がマウスカーソル付近に表示される

#### Scenario: Cursor position starts unpinned

- **WHEN** profile `notify` の position が `cursor` と定義されている
- **THEN** Ad-hoc Note は unpinned 状態で開始し、フォーカスを失ったとき自動的に非表示になる

### Requirement: CLI --id flag for window identity

`chirami display` コマンドに `--id <value>` フラグを追加する。同一 ID の Ad-hoc Note が存在する場合はコンテンツを差し替え、存在しない場合は新規作成する。

#### Scenario: First display with id

- **WHEN** `chirami display --profile agent --id session1 "Thinking..."` を実行し、id `session1` の Ad-hoc Note が存在しない
- **THEN** 新しい Ad-hoc Note が作成され、`session1` として管理される

#### Scenario: Update existing window by id

- **WHEN** id `session1` の Ad-hoc Note が表示中に `chirami display --profile agent --id session1 "Result: done"` を実行
- **THEN** 既存の Ad-hoc Note のコンテンツが `Result: done` に差し替えられ、新しいウィンドウは作成されない

#### Scenario: Display without id creates new window each time

- **WHEN** `chirami display --profile notify "First"` に続いて `chirami display --profile notify "Second"` を実行（どちらも --id なし）
- **THEN** 2つの独立した Ad-hoc Note が表示される

#### Scenario: Update existing window with different profile

- **WHEN** `chirami display --profile agent --id s1 "A"` で表示後、`chirami display --profile notify --id s1 "B"` を実行
- **THEN** 既存ウィンドウが閉じられ、notify profile の設定（色・タイトル等）で新しい Ad-hoc Note が作成される。ウィンドウの位置・サイズは引き継がれる

#### Scenario: --wait with --id replacing existing window

- **WHEN** id `s1` の Ad-hoc Note が表示中に `chirami display --id s1 --wait "New content"` を実行
- **THEN** 既存ウィンドウが差し替えられ、新しい Ad-hoc Note がユーザーに閉じられるまで CLI がブロックする。差し替えで閉じられた旧ウィンドウは FIFO への通知を行わない

### Requirement: Profile hotkey toggles all Ad-hoc Notes

profile に hotkey が設定されている場合、そのホットキーで profile に属する全 Ad-hoc Note の表示/非表示を一括トグルする。

#### Scenario: Toggle profile windows

- **WHEN** `notify` profile に hotkey `cmd+shift+n` が設定されており、notify profile で 2 つの Ad-hoc Note が表示中
- **THEN** `cmd+shift+n` を押すと 2 つのウィンドウが同時に非表示になり、再度押すと同時に表示される

#### Scenario: No Ad-hoc Notes for profile

- **WHEN** `notify` profile に hotkey が設定されているが、notify profile の Ad-hoc Note が 1 つも存在しない
- **THEN** ホットキーを押しても何も起きない

#### Scenario: Toggle with mixed visibility

- **WHEN** `notify` profile で 3 つの Ad-hoc Note が存在し、2 つが表示中・1 つが非表示の状態で hotkey を押す
- **THEN** 全ウィンドウが非表示になる（一部でも表示中なら全非表示にする。全非表示の場合のみ全表示にする）

### Requirement: Window state persistence for id-based Ad-hoc Notes

`--id` 付きで表示された Ad-hoc Note の位置・サイズを state.yaml に保存する。キーは `display:<id>` 形式。次回同じ id で表示する際に復元する。

#### Scenario: State saved on window move

- **WHEN** id `session1` の Ad-hoc Note をドラッグして位置を変更
- **THEN** state.yaml の `windows.display:session1` に新しい位置が保存される

#### Scenario: State restored on re-display

- **WHEN** state.yaml に `display:session1` の位置情報が保存されている状態で `chirami display --id session1 "content"` を実行
- **THEN** Ad-hoc Note が保存された位置に表示される

#### Scenario: No state for id-less windows

- **WHEN** `--id` なしで `chirami display --profile notify "content"` を実行
- **THEN** state.yaml にウィンドウ状態は保存されない
