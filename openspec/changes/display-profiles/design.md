## Context

Chirami の付箋ウィンドウ（Note）には2種類の作り方がある:

- **Registered Note**: config.yaml の `notes[]` に登録。常にファイルに紐づき、アプリ起動中は永続的に存在する
- **Ad-hoc Note**: CLI (`chirami display`) で都度作成。テキスト・ファイル・stdin からコンテンツを受け取る。ファイル指定時は editable

両方とも同じ付箋ウィンドウであり、見た目設定（color, transparency, fontSize, position, autoHide, title）は共通。現状 Ad-hoc Note はハードコードデフォルトで表示され、見た目の設定手段がない。

既存の Registered Note では `NoteConfig` → ハードコードデフォルトの resolve チェーンで設定を解決している。Ad-hoc Note でも同様のパターンを、profile 経由で適用する。

## Goals / Non-Goals

**Goals:**

- config.yaml に `display.profiles` セクションを追加し、Ad-hoc Note の名前付き設定プリセット（profile）を定義可能にする
- CLIから `--profile <name>` で profile を指定可能にする
- profile に hotkey を設定し、その profile で開いた全 Ad-hoc Note を一括トグル可能にする
- `--id` で同一ウィンドウの内容更新を可能にする
- state.yaml に Ad-hoc Note ウィンドウの状態（位置・サイズ）を保存する
- Ad-hoc Note の見た目設定を profile → ハードコードデフォルトの resolve チェーンで解決する

**Non-Goals:**

- CLI 引数による個別設定の上書き（将来の拡張として残す）
- profile の動的な追加・削除（config.yaml 編集 → config reload で対応）
- Ad-hoc Note ウィンドウ間のインタラクション

## Decisions

### 1. 概念モデル: Note の統一

全ての付箋ウィンドウを **Note** として統一的に扱う。

| | Registered Note | Ad-hoc Note |
|---|---|---|
| 作り方 | config.yaml に登録 | CLI で都度作成 |
| コンテンツ | 常にファイル | ファイル / テキスト / stdin |
| 編集 | editable | ファイル指定時は editable |
| ライフサイクル | 永続 | 一時的 |
| Hotkey スコープ | 1 ウィンドウ単位 | profile 単位 |

見た目設定（color, transparency, fontSize, position, autoHide, title）は共通。

### 2. Config モデル: `DisplayConfig` + `DisplayProfile` を新設

Ad-hoc Note 用の設定を `display` セクション配下に置く。Registered Note の `notes[]` とは構造的に分離し、用途の違いを明示する。

```swift
struct DisplayConfig: Codable {
    var profiles: [String: DisplayProfile]?
}

struct DisplayProfile: Codable {
    var title: String?
    var color: String?
    var transparency: Double?
    var fontSize: Int?
    var position: String?       // "cursor" | nil
    var autoHide: Bool?
    var hotkey: String?

    enum CodingKeys: String, CodingKey {
        case title, color, transparency, position, hotkey
        case fontSize = "font_size"
        case autoHide = "auto_hide"
    }
}
```

`ChiramiConfig` に `display: DisplayConfig?` を追加。profile へのアクセスは `config.display?.profiles?[name]`。

**代替案:** `NoteConfig` を再利用 → `path` が必須で意味が合わないため却下。共通部分は将来的に protocol で抽出可能。

### 3. 設定の resolve 順序

```
Registered Note: note inline → hardcoded
Ad-hoc Note:     profile     → hardcoded
```

Registered Note と Ad-hoc Note が同じ 2 段階の fallback チェーンを共有することで、設定の一貫性を保つ。共通設定が必要な場合は YAML anchor (`&` / `<<: *`) で実現する。

```yaml
notes:
  - path: ~/todo.md
    color: blue
    hotkey: cmd+shift+t

display:
  profiles:
    notify:
      color: pink
      auto_hide: true
      hotkey: cmd+shift+n
```

`DisplayProfile` の resolve メソッドはハードコードデフォルトへのフォールバックのみ。

### 4. URI パラメータの拡張

CLI から `profile=<name>` と `id=<value>` を URI に追加。

```
chirami://display?profile=notify&content=Build%20done!
chirami://display?profile=agent&id=session1&content=Thinking...
```

Swift 側の `DisplayWindowManager.display(url:)` で `profile` パラメータを読み取り、`AppConfig.shared.config.display?.profiles?[profileName]` から設定を取得。

### 5. ウィンドウ管理: id ベースの辞書

現在の `controllers: [ObjectIdentifier: DisplayWindowController]` に加え、`--id` 付きウィンドウ用に `namedControllers: [String: DisplayWindowController]` を追加。

- `--id` なし → 新規ウィンドウ作成、`controllers` に格納
- `--id` あり → `namedControllers[id]` が存在すれば既存ウィンドウを閉じて新規作成（profile が変わる場合に色・設定も反映するため）、なければ単純に新規作成して格納

### 6. Profile hotkey: 一括トグル

Profile hotkey は、その profile 名で開かれた全 Ad-hoc Note をトグルする。
`DisplayWindowController` に `profileName: String?` を保持し、hotkey 発火時に `controllers` + `namedControllers` をフィルタしてトグル。

`ChiramiApp.registerAllHotkeys()` に profile hotkey 登録を追加。

### 7. State 保存

`--id` 付きの Ad-hoc Note のみ、state.yaml にウィンドウ状態を保存する。id なしは一時的なので保存しない。

state キー: `display:<id>`（既存 Registered Note のキーと衝突しないよう prefix 付与）

## Risks / Trade-offs

- **profile 名の衝突リスク** → profile キーは config.yaml でユーザーが管理するため、重複は YAML レベルで防がれる
- **`--wait` と `--id` の相互作用** → `--id` で既存ウィンドウを差し替える場合、古いウィンドウの close 時に FIFO へ `CLOSED` を書き込まないようにする必要がある。`--wait` は最終的にウィンドウが閉じられるまでブロックする
- **config reload 時の hotkey 再登録** → 既存の `noteStore.$notes.sink` と同様のパターンで `AppConfig` の変更を監視する必要がある
- **ハードコードデフォルトの共有** → Registered Note と Ad-hoc Note が同じハードコードデフォルト値を共有する。共通設定が必要な場合は YAML anchor で対応
