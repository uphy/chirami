# Idea: chirami append

ステータス: 未実装（アイデア）

## Why

CLI やスクリプトからタスクやメモを素早く特定ノートへ追記したいが、毎回ファイルパスを指定するのは煩雑で、daily note のような日付ベースのパスは手動解決が難しい。Chirami.app はすでにノートのパスを管理しているため、アプリ経由で追記すればパスを意識せずに使える。

## What

- `chirami append` サブコマンドを Go CLI に追加する
- URI scheme `chirami://append` を Chirami.app に実装する
- config.yaml の `NoteConfig` に任意の `id` フィールドを追加する
  - 指定した場合はその文字列をそのまま note ID として使用する
  - 未指定の場合は従来通り path の SHA256 から自動生成する
- ノートは `id` で指定する（例: `chirami append daily "- [ ] タスク"`）
- ウィンドウ表示・ブロッキングなし（fire-and-forget）

## 想定インターフェース

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

## 影響範囲（検討時点）

- `ConfigModels.swift` の `NoteConfig` に `id`（optional String）を追加
- `NoteConfig.noteId` を更新（explicit id 優先、フォールバックで hash）
- `cmd/chirami/append.go` を追加
- `cmd/chirami/internal/uri.go` に `append` 用 URI ビルダーを追加
- `Chirami/` に `chirami://append` URI ハンドラを追加
