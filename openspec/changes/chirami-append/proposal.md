## Why

CLI やスクリプトからタスクやメモを素早く特定ノートへ追記したいが、毎回ファイルパスを指定するのは煩雑で、daily note のような日付ベースのパスは手動解決が難しい。Chirami.app はすでにノートのパスを管理しているため、アプリ経由で追記することでパスを意識せずに使える。

## What Changes

- `chirami append` サブコマンドを Go CLI に追加する
- URI scheme `chirami://append` を Chirami.app に実装する
- config.yaml の `NoteConfig` に任意の `id` フィールドを追加する
  - 指定した場合はその文字列をそのまま note ID として使用する
  - 未指定の場合は従来通り path の SHA256 から自動生成する
- `chirami append` はノートを `id` で指定する（例: `chirami append daily "- [ ] タスク"`）
- ウィンドウ表示・ブロッキングなし（fire-and-forget）

## Capabilities

### New Capabilities

- `note-id`: config.yaml で note に任意の `id` を付与できる。未指定時は path ハッシュで自動生成（既存挙動）
- `cli-append`: CLI からコンテンツを受け取り、指定 note ID のノートへ追記する

### Modified Capabilities

- `cli-display`: `chirami` Go CLI のサブコマンド構造を共有する（実装の共通化のみ、要件変更なし）

## Impact

- `ConfigModels.swift` の `NoteConfig` に `id` フィールド（optional String）を追加する
- `NoteConfig.noteId` を更新する（explicit id 優先、フォールバックで hash）
- `cmd/chirami/append.go` を追加する（Go CLI サブコマンド）
- `cmd/chirami/internal/uri.go` に `append` 用 URI ビルダーを追加する
- `Chirami/` に `chirami://append` URI ハンドラを追加する

## Config 例

```yaml
notes:
  - path: ~/notes/{date}.md
    id: daily
  - path: ~/notes/scratch.md
    id: scratch
  - path: ~/notes/work.md
    # id 未指定 → path ハッシュで自動生成
```

```bash
chirami append daily "- [ ] 牛乳を買う"
chirami append scratch "## メモ\n内容"
```
