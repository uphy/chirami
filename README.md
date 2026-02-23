# Fusen

macOS 付箋型 Markdown ノートアプリ。Stickies のシンプルさと Obsidian の Live Preview を、plain `.md` ファイルで実現する。

## 設計思想

- **Markdown ファイルはユーザーのもの** — pure Markdown のみ（メタデータなし）。Obsidian・VS Code・任意のエディタと完全互換。
- **Config と State の分離** — ノート一覧・外観設定は `config.yaml`（dotfiles 管理可能）。ウィンドウ位置・サイズ・表示状態は `state.yaml`（揮発的）。
- **ノートは個別パス指定** — ディレクトリに縛られない。プロジェクトの `todo.md`、`~/Notes/meeting.md` など任意のパスを登録。
- **最小限の装飾** — 付箋としての軽さを損なわない。タイトルバーを隠し、常に最前面、半透明対応。
- **Live Preview** — カーソルのあるブロックだけ raw Markdown、他はレンダリング済み（Obsidian 風）。

## 機能

- 複数ノート（各ノートが独立ウィンドウ）
- Markdown Live Preview（見出し・太字・斜体・コード・リンク・リスト）
- 常に最前面表示（always-on-top）
- ノートごとの半透明設定
- ノートごとの背景色（6色プリセット）
- ノートごとのフォントサイズ設定
- ノートごとのグローバルホットキーで表示/非表示トグル
- コードブロックの Syntax Highlighting
- メニューバーアイコンからノート管理
- 外部エディタでの変更を即時反映（DispatchSource ファイル監視）
- ウィンドウ位置・サイズを次回起動時に復元

## 設定

### config.yaml (`~/.config/fusen/config.yaml`)

dotfiles で管理する安定した設定。

```yaml
notes:
  - id: meeting
    path: ~/Notes/meeting.md
    title: 会議メモ
    color: yellow
    transparency: 0.9
    font_size: 14
    hotkey: cmd+shift+m
  - id: todo
    path: ~/projects/todo.md
    color: blue
  - id: scratch
    path: ~/Desktop/scratch.md
```

**フィールド:**
- `id`: ノート識別子（省略時はファイル名から自動生成）
- `path`: 絶対パスまたは `~/` 相対パス（必須）
- `title`: ウィンドウタイトル（省略時は `id`）
- `color`: 背景色（`yellow` / `blue` / `green` / `pink` / `purple` / `gray`）
- `transparency`: ウィンドウの不透明度（0.0〜1.0）
- `font_size`: フォントサイズ（px）
- `hotkey`: グローバルホットキー（例: `cmd+shift+m`）

### state.yaml (`~/.local/state/fusen/state.yaml`)

アプリが自動管理する揮発的な状態。通常手動編集は不要。

```yaml
windows:
  meeting:
    position: [100, 200]
    size: [300, 400]
    visible: true
    always_on_top: true
  todo:
    position: [450, 200]
    size: [280, 350]
    visible: false

bookmarks:
  meeting: <Base64 encoded security-scoped bookmark>
```

## ビルド・実行

**依存ツール:**

```bash
brew install xcodegen
```

**プロジェクト生成:**

```bash
cd /path/to/fusen
xcodegen generate
open Fusen.xcodeproj
```

Xcode でビルド・実行（⌘R）。SPM パッケージは初回ビルド時に自動取得される。

**swift build でのビルド:**

```bash
swift build
```

**mise タスク:**

```bash
mise run generate  # xcodegen でプロジェクトファイルを生成
mise run build     # Release ビルド（.app バンドル生成）
mise run apply     # ~/Applications にインストール
mise run clean     # ビルド成果物を削除
mise run lint      # SwiftLint で静的解析を実行
mise run lint-fix  # SwiftLint で自動修正を実行
```

## 依存ライブラリ

| ライブラリ | 用途 | ライセンス |
|-----------|------|-----------|
| [swift-markdown](https://github.com/swiftlang/swift-markdown) | Markdown パーサー（Apple 公式） | Apache 2.0 |
| [HotKey](https://github.com/soffes/HotKey) | グローバルホットキー | MIT |
| [Yams](https://github.com/jpsim/Yams) | YAML パーサー | MIT |
| [Highlightr](https://github.com/raspu/Highlightr) | コードブロックの Syntax Highlighting | MIT |

## アーキテクチャ

```
Fusen/
├── FusenApp.swift          # @main, MenuBarExtra, AppDelegate
├── Models/
│   ├── Note.swift          # ノートモデル（id, title, path, color）
│   └── NoteStore.swift     # config からノート一覧管理、ファイル CRUD
├── Views/
│   ├── NoteWindow.swift    # NSPanel + NoteContentView（always-on-top, 半透明）
│   ├── LivePreviewEditor.swift   # NSTextView ベース Live Preview エディタ
│   └── NoteListPopover.swift     # メニューバー用ノート一覧
├── Editor/
│   ├── MarkdownStyler.swift      # MD AST → NSAttributedString + カーソル位置特定
│   └── BulletLayoutManager.swift # 箇条書き・コードブロック背景・blockquote 描画
├── Config/
│   ├── AppConfig.swift           # config.yaml 読み書き
│   ├── AppState.swift            # state.yaml 読み書き
│   └── ConfigModels.swift        # YAML 構造体定義
└── Services/
    ├── GlobalHotkeyService.swift  # グローバルホットキー登録
    ├── WindowManager.swift        # 全ウィンドウ制御
    └── FileWatcher.swift          # ファイル変更監視
```
