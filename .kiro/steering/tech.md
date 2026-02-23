# Technology Stack

## Architecture

AppKit + SwiftUI ハイブリッド構成の macOS ネイティブアプリ。テキスト描画は AppKit (NSTextView, NSLayoutManager) で制御し、メニュー UI は SwiftUI で構築。Combine による Reactive なデータフローで設定変更を即時反映する。

## Core Technologies

- **Language**: Swift 5.9+
- **Platform**: macOS 14.0+ (Sonoma)
- **UI**: AppKit (NSPanel, NSTextView, NSLayoutManager) + SwiftUI (MenuBarExtra)
- **Reactive**: Combine (ObservableObject, @Published)

## Key Libraries

- **swift-markdown** (Apple) — Markdown AST パース
- **HotKey** — グローバルホットキー登録
- **Yams** — YAML パース (設定ファイル)
- **Highlightr** — コードブロックのシンタックスハイライト

## Development Standards

### Build System

- **XcodeGen** — `project.yml` から `.xcodeproj` を生成
- **Swift Package Manager** — 依存管理
- **mise** — タスクランナー

### Config/State 分離

- `~/.config/chirami/config.yaml` — ユーザー設定 (dotfiles 管理可能)
- `~/.local/state/chirami/state.yaml` — アプリ管理のウィンドウ状態 (ephemeral)
- YAML を採用し、人間が読み書きしやすく、バージョン管理に適した形式

### Concurrency

- `@MainActor` をシングルトンに付与し、メインスレッド実行を保証
- DispatchSource によるファイル監視 (0.2s debounce)

## Common Commands

```bash
mise run generate  # XcodeGen で .xcodeproj 生成
mise run build     # Release ビルド → .app バンドル (build/)
mise run apply     # ~/Applications にインストール
mise run clean     # ビルド成果物削除
```

## Key Technical Decisions

- **AppKit + SwiftUI ハイブリッド** — SwiftUI だけでは NSPanel (フローティング) や NSLayoutManager (カスタム描画) が使えないため、テキスト編集は AppKit、メニュー UI は SwiftUI で分担
- **Security-scoped bookmarks** — macOS sandbox 下で安全にファイルアクセスを永続化
- **YAML over JSON/Plist** — dotfiles との親和性を重視
- **Live Preview 方式** — AST をブロック単位で走査し、カーソル位置のブロックのみ raw 表示にすることで、編集と閲覧を同一ビューで実現
