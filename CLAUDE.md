# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロダクトビジョン

@docs/product-vision.md

## プロジェクト概要

Fusen は macOS 付箋型 Markdown ノートアプリ。Stickies のシンプルさと Obsidian の Live Preview を plain `.md` ファイルで実現する。メニューバー常駐型（LSUIElement）で、各ノートは独立した NSPanel ウィンドウとして表示される。

## ビルド

```bash
# 初回セットアップ（xcodegen が必要）
brew install xcodegen
xcodegen generate

# ビルド・実行は Xcode で
open Fusen.xcodeproj
# Xcode で ⌘R
```

Xcode プロジェクトは `project.yml` から xcodegen で生成する。`Fusen.xcodeproj` を直接編集せず、`project.yml` を変更して `xcodegen generate` を再実行すること。

SPM 依存は初回ビルド時に自動取得される。`swift build` でもビルド可能（Package.swift あり）。

### mise タスク

`.mise/tasks/` にビルド・デプロイ用のタスクを定義している。

- `mise run generate` — xcodegen でプロジェクトファイルを生成
- `mise run build` — Release ビルド（.app バンドル生成）
- `mise run apply` — `~/Applications` にインストール（実行中なら再起動）
- `mise run clean` — ビルド成果物を削除

## Note 種別

| 用語 | 定義 | コード上の主要クラス |
|------|------|---------------------|
| **Registered Note** | config.yaml の `notes[]` に登録されたノート。Static Note と Periodic Note を含む | `NoteStore`, `WindowManager`, `NoteWindowController` |
| **Ad-hoc Note** | CLI (`chirami display`) から動的に作成されるノート | `DisplayWindowManager`, `DisplayWindowController` |
| **Static Note** | Registered Note のうち、固定パスのもの | — |
| **Periodic Note** | Registered Note のうち、日付テンプレートパスのもの | `PeriodicNoteInfo`, `PathTemplateResolver` |

## アーキテクチャ

### Config/State 分離

- `~/.config/fusen/config.yaml` — ノート一覧・外観設定（dotfiles 管理可能）
- `~/.local/state/fusen/state.yaml` — ウィンドウ位置・サイズ・表示状態（揮発的、アプリが自動管理）

YAML の読み書きには Yams を使用。構造体定義は `Config/ConfigModels.swift`。

### Singleton パターン

主要サービスは Singleton + `@MainActor` で統一:

- `NoteStore.shared` — ノート管理・ファイル I/O
- `AppConfig.shared` — config.yaml 読み書き
- `AppState.shared` — state.yaml 読み書き
- `WindowManager.shared` — 全ウィンドウ制御

### NSPanel + SwiftUI ハイブリッド

ノートウィンドウは AppKit の `NSPanel`（always-on-top 対応）に SwiftUI View をホストする構成。`NoteWindow.swift` に `NotePanel`, `NoteWindowController`, `NoteContentView` が同居。

### Live Preview エディタ

Obsidian 風の Live Preview を実現するコア部分:

- `LivePreviewEditor` — NSViewRepresentable で NSTextView をラップ
- `MarkdownStyler` — swift-markdown の AST を NSAttributedString に変換。カーソルのあるブロックだけ raw Markdown を表示し、他ブロックはレンダリング済みにする。カーソル位置がどのブロックに属するかの特定もここで行う
- `BulletLayoutManager` — カスタム NSLayoutManager。箇条書きの描画、コードブロック背景、blockquote の border 描画を担当

**注意**: MarkdownStyler では UTF-8 と String.Index/NSRange の変換が重要。非 ASCII テキスト（日本語）でのオフセット計算に注意が必要。

### 依存ライブラリ

| ライブラリ | 用途 |
|-----------|------|
| swift-markdown | Markdown AST パーサー |
| HotKey | グローバルホットキー登録 |
| Yams | YAML パーサー |
| Highlightr | コードブロックの Syntax Highlighting |