## Why

CLI (`chirami display`) で Ad-hoc Note を表示できるが、色・位置・透過度などの見た目設定はすべてハードコードされており、用途に応じてカスタマイズする手段がない。コマンド完了通知、agent 出力表示、インタラクティブ確認など用途ごとに見た目を変えたいため、config.yaml で名前付きプリセット（profile）を定義し、CLI からは profile 名を指定するだけで使えるようにしたい。

## What Changes

- config.yaml に `adhoc.profiles` セクションを追加。各 profile は Ad-hoc Note の設定プリセット兼グルーピング単位
- CLI に `--profile <name>` フラグを追加。指定された profile の設定でウィンドウを表示
- profile に hotkey を設定可能。その profile で表示された全 Ad-hoc Note を一括トグル
- `--profile` 省略時はハードコードデフォルトの設定で表示
- `--id` 付きウィンドウの位置・サイズを state.yaml に保存

## Capabilities

### New Capabilities

- `display-profiles`: config.yaml での profile 定義、CLI からの profile 指定、profile 単位の hotkey・ウィンドウ状態管理

### Modified Capabilities

（既存 spec なし）

## Impact

- **Config**: `ConfigModels.swift` に `AdhocConfig`, `AdhocProfile` 構造体追加、`ChiramiConfig` に `adhoc` フィールド追加
- **Config**: resolve メソッドは `profile → hardcoded` の 2 段階フォールバック
- **CLI (Go)**: `display.go` に `--profile` フラグ追加、URI パラメータに `profile=<name>` 追加
- **App (Swift)**: URI handler で profile パラメータを解釈し、対応する設定を適用。`DisplayWindowManager` で profile 別ウィンドウ管理
- **State**: `ChiramiState` に Ad-hoc Note ウィンドウの状態保存を追加（キー: `adhoc:<id>`）
- **Hotkey**: `GlobalHotkeyService` に profile 用ホットキー登録を追加
