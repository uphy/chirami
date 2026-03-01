## 1. Config モデル

- [ ] 1.1 `ConfigModels.swift` に `DisplayConfig` 構造体を追加（`profiles: [String: DisplayProfile]?`）
- [ ] 1.2 `ConfigModels.swift` に `DisplayProfile` 構造体を追加（title, color, transparency, fontSize, position, hotkey + CodingKeys）
- [ ] 1.3 `ChiramiConfig` に `display: DisplayConfig?` フィールドを追加
- [ ] 1.4 `DisplayProfile` に resolve メソッド群を追加（resolveColor, resolveTransparency, resolveFontSize, resolvePosition。fallback: `profile → hardcoded`）

## 2. CLI (Go)

- [ ] 2.1 `display.go` に `--profile` フラグを追加し、URI パラメータ `profile=<name>` として渡す
- [ ] 2.2 `display.go` に `--id` フラグを追加し、URI パラメータ `id=<value>` として渡す

## 3. Ad-hoc Note ウィンドウへの設定適用

- [ ] 3.1 `DisplayPanel.init` を拡張し、color・transparency・title を受け取れるようにする
- [ ] 3.2 `DisplayContentView` を拡張し、fontSize を受け取れるようにする
- [ ] 3.3 `DisplayWindowController` に profileName プロパティを追加
- [ ] 3.4 `DisplayWindowController` に position（cursor）対応を追加
- [ ] 3.5 `DisplayWindowController` に pin/unpin 対応を追加（unpinned 時は windowDidResignKey で非表示）

## 4. DisplayWindowManager の拡張

- [ ] 4.1 `display(url:)` で `profile` パラメータを読み取り、`AppConfig.shared.config.display?.profiles?[name]` から `DisplayProfile` を取得。resolve メソッドでハードコードデフォルトにフォールバック
- [ ] 4.2 `--id` 対応: `namedControllers: [String: DisplayWindowController]` を追加し、同一 id の Ad-hoc Note が存在すれば既存を閉じて新規作成（位置・サイズは引き継ぎ、差し替え時の close では FIFO 通知しない）
- [ ] 4.3 id なしウィンドウの従来の管理（`controllers` 辞書）を維持

## 5. Profile hotkey

- [ ] 5.1 `ChiramiApp.registerAllHotkeys()` に profile hotkey の登録を追加
- [ ] 5.2 `DisplayWindowManager` に profile 名で全 Ad-hoc Note をトグルするメソッドを追加（一部でも表示中なら全非表示、全非表示なら全表示）
- [ ] 5.3 config reload 時に profile hotkey を再登録する（`AppConfig` の変更を監視）

## 6. State 永続化

- [ ] 6.1 `--id` 付き Ad-hoc Note の位置・サイズを state.yaml に保存（キー: `display:<id>`）
- [ ] 6.2 `--id` 付き Ad-hoc Note 表示時に保存済みの位置・サイズを復元
