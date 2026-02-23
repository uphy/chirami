# Project Structure

## Organization Philosophy

責務ごとにディレクトリを分割するレイヤードアーキテクチャ。Models / Views / Editor / Config / Services の 5 層で構成。各層は単一責務を持ち、依存方向は上位層 → 下位層。

## Directory Patterns

### Models (`Fusen/Models/`)

データモデルと永続化ロジック。Foundation のみに依存し、UI フレームワークに依存しない。

- `Note` — ノートの構造体 + カラー定義
- `NoteStore` — ノート一覧の管理、ファイル I/O、ブックマーク

### Views (`Fusen/Views/`)

SwiftUI と AppKit の UI 層。NSViewRepresentable でブリッジ。

- `NoteWindow` — NSPanel サブクラス + WindowController
- `LivePreviewEditor` — NSTextView の SwiftUI ラッパー
- `MarkdownTextView` — NSTextView サブクラス (チェックボックス・リンク操作)
- `NoteListPopover` — メニューバーのノート一覧 (SwiftUI)

### Editor (`Fusen/Editor/`)

Markdown レンダリングとスタイリング。最大のサブシステム。

- `MarkdownStyler` — AST → NSAttributedString 変換のコア
- `MarkdownStyler+*.swift` — ブロック種別ごとの拡張 (Heading, CodeBlock, List, Table, etc.)
- `BulletLayoutManager` — NSLayoutManager サブクラス (カスタム背景描画)

### Config (`Fusen/Config/`)

設定と状態の管理。YAML ベースの永続化と Reactive な更新。

- `YAMLStore<T>` — 汎用的な YAML ストア (ファイル監視 + Combine 連携)
- `AppConfig` / `AppState` — 設定/状態の Codable 定義

### Services (`Fusen/Services/`)

横断的なサービス層。

- `WindowManager` — 全ウィンドウの制御
- `GlobalHotkeyService` — ホットキー登録・解除
- `FileWatcher` — DispatchSource ベースのファイル変更検知

## Naming Conventions

- **ファイル/型**: PascalCase (`MarkdownStyler`, `NoteWindow`)
- **Extension ファイル**: `型名+機能.swift` (`MarkdownStyler+Inline.swift`)
- **変数/関数**: camelCase
- **コールバック**: `onXxx` prefix (`onCheckboxClick`, `onFontSizeChange`)
- **シングルトン**: `static let shared` パターン、`@MainActor` 付与
- **YAML キー**: snake_case → `CodingKeys` で camelCase にマッピング

## Import Organization

```swift
import SwiftUI       // UI フレームワーク
import AppKit        // ネイティブ UI
import Combine       // Reactive
import Markdown      // AST パース
import HotKey        // ホットキー
```

- Views は SwiftUI + AppKit の両方を import (ハイブリッド)
- Services は Foundation + Darwin のみ
- Models は Foundation のみ

## Code Organization Principles

- **Extension による分割** — 大きな型はブロック種別・機能ごとに `+Feature.swift` で分割
- **Closure ベースのコールバック** — Delegate パターンではなく、`onXxx` クロージャで疎結合に接続
- **カスタム NSAttributedString.Key** — `.codeBlockBackground`, `.blockQuoteBorder` 等のマーカー属性でレンダリング層とスタイリング層を分離
- **Reactive データフロー** — `@Published` → `@ObservedObject` の Combine チェーンで設定変更を即時 UI に反映
