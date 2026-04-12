# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロダクトビジョン

@docs/product-vision.md

## プロジェクト概要

Chirami は macOS 付箋型 Markdown ノートアプリ。Stickies のシンプルさと Obsidian の Live Preview を plain `.md` ファイルで実現する。メニューバー常駐型（LSUIElement）で、各ノートは独立した NSPanel ウィンドウとして表示される。

## ビルド

```bash
# 初回セットアップ（xcodegen が必要）
brew install xcodegen
xcodegen generate

# ビルド・実行は Xcode で
open Chirami.xcodeproj
# Xcode で ⌘R
```

Xcode プロジェクトは `project.yml` から xcodegen で生成する。`Chirami.xcodeproj` を直接編集せず、`project.yml` を変更して `xcodegen generate` を再実行すること。

SPM 依存は初回ビルド時に自動取得される。`swift build` でもビルド可能（Package.swift あり）。

### mise タスク

`.mise/tasks/` にビルド・デプロイ用のタスクを定義している。

- `mise run generate` — xcodegen でプロジェクトファイルを生成
- `mise run build` — Release ビルド（.app バンドル生成）
- `mise run apply` — `~/Applications` にインストール（実行中なら再起動）
- `mise run clean` — ビルド成果物を削除
- `mise run build:editor` — `editor-web/` の TypeScript をビルドして `Chirami/Resources/editor/` に出力

## Note 種別

| 用語 | 定義 | コード上の主要クラス |
|------|------|---------------------|
| **Registered Note** | config.yaml の `notes[]` に登録されたノート。Static Note と Periodic Note を含む | `NoteStore`, `WindowManager`, `NoteWindowController` |
| **Ad-hoc Note** | CLI (`chirami display`) から動的に作成されるノート | `DisplayWindowManager`, `DisplayWindowController` |
| **Static Note** | Registered Note のうち、固定パスのもの | — |
| **Periodic Note** | Registered Note のうち、日付テンプレートパスのもの | `PeriodicNoteInfo`, `PathTemplateResolver` |

## アーキテクチャ

### Config/State 分離

- `~/.config/chirami/config.yaml` — ノート一覧・外観設定（dotfiles 管理可能）
- `~/.local/state/chirami/state.yaml` — ウィンドウ位置・サイズ・表示状態（揮発的、アプリが自動管理）

YAML の読み書きには Yams を使用。構造体定義は `Config/ConfigModels.swift`。

### Singleton パターン

主要サービスは Singleton + `@MainActor` で統一:

- `NoteStore.shared` — ノート管理・ファイル I/O
- `AppConfig.shared` — config.yaml 読み書き
- `AppState.shared` — state.yaml 読み書き
- `WindowManager.shared` — 全ウィンドウ制御

### NSPanel + SwiftUI ハイブリッド

ノートウィンドウは AppKit の `NSPanel`（always-on-top 対応）に SwiftUI View をホストする構成。`NoteWindow.swift` に `NotePanel`, `NoteWindowController`, `NoteContentView` が同居。

### WebView エディタ

Obsidian 風の Live Preview は WKWebView + CodeMirror 6 で実現している。

- `NoteWebView` — WKWebView をラップした NSView。Swift と JS のメッセージングを管理する
- `NoteWebViewBridge` — `WKScriptMessageHandler` 実装。JS → Swift メッセージを受信してコールバックに転送
- `editor-web/` — TypeScript/CodeMirror 6 ソース。`mise run editor-build` でビルドして `Chirami/Resources/editor/` に出力される

**データフロー**: `NoteContentModel.text` ↔ `NoteWebView`（evaluateJavaScript / WKScriptMessageHandler）↔ CodeMirror 6 state

**注意**: JS ↔ Swift 間のカーソルオフセットは UTF-16 コードユニット単位。`NoteWebViewBridge` でのオフセット受け渡し時は単位を意識すること。

### 依存ライブラリ

**Swift (SPM)**

| ライブラリ | 用途 |
|-----------|------|
| HotKey | グローバルホットキー登録 |
| Yams | YAML パーサー |

**JS (editor-web/)**

| ライブラリ | 用途 |
|-----------|------|
| CodeMirror 6 | Live Preview エディタエンジン |
| turndown | HTML → Markdown 変換（Smart Paste） |

## ログ実装ルール

- `NSLog` / `print` は使用禁止。必ず `os.Logger` を使用する
- subsystem は `"io.github.uphy.Chirami"` で統一
- category はクラス名・ファイル名に対応させる
- 動的な値（パス・エラー・URL）は `privacy: .public` を指定する

### Logger 定義場所

- クラス内 instance property または `static let`（enum の場合）として定義する

### ログレベル指針

| 状況 | レベル |
|------|--------|
| デバッグ情報（URL受信・処理開始など） | `.debug` |
| 正常完了の記録（〇件削除、保存成功） | `.info` |
| 設定ミス・リソース不存在の警告 | `.warning` |
| 処理の失敗・エラー | `.error` |

### ログ確認方法

ターミナルで以下を実行してからアプリを起動する：

```bash
log stream --predicate 'subsystem == "io.github.uphy.Chirami"' --level debug
```

category で絞る場合：

```bash
log stream --predicate 'subsystem == "io.github.uphy.Chirami" AND category == "NoteWebView"' --level debug
```

エラーのみ確認する場合：

```bash
log stream --predicate 'subsystem == "io.github.uphy.Chirami"' --level error
```