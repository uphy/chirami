# Chirami

A macOS sticky-note Markdown app. Access your notes as floating windows — without breaking your flow.

> **Chirami** — from the Japanese word *chirami* (ちら見), meaning "a quick glance." Glance at your notes without interrupting your work.

## Features

- **Markdown Live Preview** — Obsidian-style editing: raw Markdown at the cursor, rendered everywhere else
- **Always-on-top floating windows** — `NSPanel`-based sticky notes that stay above all windows (tiling WM friendly)
- **Global hotkeys** — Summon any note instantly from any application
- **Pure `.md` files** — No metadata, no front matter. Full Obsidian / VS Code compatibility
- **Periodic notes** — Date-based file paths with rollover delay and templates
- **Smart Paste** — Cmd+Shift+V converts URLs, HTML, and JSON to Markdown on paste
- **Per-note styling** — Background color, transparency, and font size for each note
- **Config / State separation** — `config.yaml` is dotfiles-friendly; `state.yaml` is auto-managed

See [Features](docs/features.md) for the full feature guide and keyboard shortcuts.

## Quick Start

**Prerequisites:** macOS 14.0 (Sonoma) or later

**Install:** Download the latest `Chirami-*-macOS.zip` from [Releases](https://github.com/uphy/chirami/releases), unzip it, and move `Chirami.app` to `~/Applications`.

**Create a minimal config** at `~/.config/chirami/config.yaml`:

```yaml
notes:
  - path: ~/Notes/todo.md
```

Launch Chirami — it appears as a menu bar icon. Click it to toggle your notes.

See [Getting Started](docs/getting-started.md) for the full setup guide.

## Configuration

Chirami uses two files:

- **`~/.config/chirami/config.yaml`** — User-managed settings (dotfiles-friendly)
- **`~/.local/state/chirami/state.yaml`** — Auto-managed runtime state (window positions, sizes, visibility)

```yaml
defaults:
  color: yellow
  transparency: 0.9
  font_size: 14

notes:
  - path: ~/Notes/todo.md
    title: TODO
    color: blue
    hotkey: cmd+shift+t

  - path: ~/Notes/daily/{yyyy-MM-dd}.md
    title: Daily
    color: green
    hotkey: cmd+shift+d
    rollover_delay: 2h

  - path: ~/Desktop/scratch.md
    hotkey: cmd+shift+s
    position: cursor
    auto_hide: true
```

See [Configuration](docs/configuration.md) for the full field reference.

## Documentation

- [Getting Started](docs/getting-started.md) — Installation through first note display
- [Configuration](docs/configuration.md) — Full config.yaml field reference
- [Features](docs/features.md) — Feature guide and keyboard shortcuts
- [Advanced](docs/advanced.md) — Periodic Notes, Smart Paste, Karabiner integration
- [Product Vision](docs/product-vision.md) — Why Chirami exists

## Development

**Prerequisites:** macOS 14.0 (Sonoma) or later, [mise](https://mise.jdx.dev/)

| Task | Command | Description |
|------|---------|-------------|
| Generate | `mise run generate` | Generate Xcode project via xcodegen |
| Build | `mise run build` | Release build (.app bundle) |
| Install | `mise run apply` | Copy .app to ~/Applications |
| Clean | `mise run clean` | Remove build artifacts |
| Lint | `mise run lint` | Run SwiftLint |
| Lint fix | `mise run lint-fix` | Auto-fix SwiftLint violations |

**ソースからビルド & インストール:**

```bash
mise run build && mise run apply
```

**Xcode で開発:**

```bash
xcodegen generate
open Chirami.xcodeproj
# Build and run with Cmd+R
```

## Dependencies

| Library | Purpose | License |
|---------|---------|---------|
| [swift-markdown](https://github.com/swiftlang/swift-markdown) | Markdown parser (Apple) | Apache 2.0 |
| [HotKey](https://github.com/soffes/HotKey) | Global hotkeys | MIT |
| [Yams](https://github.com/jpsim/Yams) | YAML parser | MIT |
| [Highlightr](https://github.com/raspu/Highlightr) | Code block syntax highlighting | MIT |

## License

[MIT](LICENSE)
