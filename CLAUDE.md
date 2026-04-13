# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product Vision

@docs/product-vision.md

## Overview

Chirami is a macOS sticky-note Markdown app — a floating companion for daily work. It floats what you need (notes, TODOs, memos) above your screen while you work. Built on plain `.md` files with full Obsidian compatibility. Runs as a menu bar app (LSUIElement); each note is displayed as an independent `NSPanel` window.

## Build

```bash
# Initial setup (requires xcodegen)
brew install xcodegen
xcodegen generate

# Build and run in Xcode
open Chirami.xcodeproj
# Press ⌘R in Xcode
```

The Xcode project is generated from `project.yml` via xcodegen. Do not edit `Chirami.xcodeproj` directly — modify `project.yml` and re-run `xcodegen generate`.

SPM dependencies are fetched automatically on first build. `swift build` also works (Package.swift is present).

### mise Tasks

Build and deploy tasks are defined in `.mise/tasks/`.

- `mise run generate` — Generate project file via xcodegen
- `mise run build` — Release build (produces .app bundle)
- `mise run apply` — Install to `~/Applications` (restarts if running)
- `mise run clean` — Remove build artifacts
- `mise run build:editor` — Build TypeScript in `editor-web/` and output to `Chirami/Resources/editor/`

## Note Types

| Term | Definition | Key Classes |
|------|------------|-------------|
| **Registered Note** | Notes registered in `notes[]` of config.yaml. Includes Static Notes and Periodic Notes | `NoteStore`, `WindowManager`, `NoteWindowController` |
| **Ad-hoc Note** | Notes dynamically created via CLI (`chirami display`) | `DisplayWindowManager`, `DisplayWindowController` |
| **Static Note** | A Registered Note with a fixed file path | — |
| **Periodic Note** | A Registered Note with a date-template file path | `PeriodicNoteInfo`, `PathTemplateResolver` |

## Architecture

### Config/State Separation

- `~/.config/chirami/config.yaml` — Note list and appearance settings (dotfiles-manageable)
- `~/.local/state/chirami/state.yaml` — Window position, size, and visibility (volatile, managed by the app)

YAML reading/writing uses Yams. Struct definitions are in `Config/ConfigModels.swift`.

### Singleton Pattern

Major services are unified as Singleton + `@MainActor`:

- `NoteStore.shared` — Note management and file I/O
- `AppConfig.shared` — config.yaml read/write
- `AppState.shared` — state.yaml read/write
- `WindowManager.shared` — All window control

### NSPanel + SwiftUI Hybrid

Note windows host SwiftUI Views inside AppKit `NSPanel` (always-on-top). `NoteWindow.swift` contains `NotePanel`, `NoteWindowController`, and `NoteContentView`.

### WebView Editor

Live Preview is implemented with WKWebView + CodeMirror 6.

- `NoteWebView` — NSView wrapping WKWebView. Manages Swift ↔ JS messaging
- `NoteWebViewBridge` — `WKScriptMessageHandler` implementation. Receives JS → Swift messages and forwards them via callbacks
- `editor-web/` — TypeScript/CodeMirror 6 source. Built with `mise run build:editor` and output to `Chirami/Resources/editor/`

**Data flow**: `NoteContentModel.text` ↔ `NoteWebView` (evaluateJavaScript / WKScriptMessageHandler) ↔ CodeMirror 6 state

**Note**: Cursor offsets between JS and Swift are in UTF-16 code units. Be aware of units when passing offsets through `NoteWebViewBridge`.

### Dependencies

**Swift (SPM)**

| Library | Purpose |
|---------|---------|
| HotKey | Global hotkey registration |
| Yams | YAML parser |

**JS (editor-web/)**

| Library | Purpose |
|---------|---------|
| CodeMirror 6 | Live Preview editor engine |
| mermaid | Mermaid diagram rendering |
| turndown | HTML → Markdown conversion (Smart Paste) |

## Logging Rules

- `NSLog` / `print` are prohibited. Always use `os.Logger`
- subsystem: `"io.github.uphy.Chirami"` (consistent across all loggers)
- category: match to the class or file name
- Dynamic values (paths, errors, URLs): specify `privacy: .public`

### Logger Definition

- Define as an instance property or `static let` (for enums) within the class

### Log Level Guidelines

| Situation | Level |
|-----------|-------|
| Debug info (URL received, process started, etc.) | `.debug` |
| Successful completion (N items deleted, save succeeded) | `.info` |
| Misconfiguration or missing resource | `.warning` |
| Processing failure or error | `.error` |

### Viewing Logs

Run the following in a terminal before launching the app:

```bash
log stream --predicate 'subsystem == "io.github.uphy.Chirami"' --level debug
```

Filter by category:

```bash
log stream --predicate 'subsystem == "io.github.uphy.Chirami" AND category == "NoteWebView"' --level debug
```

Errors only:

```bash
log stream --predicate 'subsystem == "io.github.uphy.Chirami"' --level error
```
