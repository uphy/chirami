# Chirami

While you work, you always need something else at hand. Chirami floats it above your screen.

> **Chirami** — from the Japanese word *chirami* (ちら見), meaning "a quick glance." Glance at your notes without interrupting your work.

## Features

- **Markdown Live Preview** — Obsidian-style editing: raw Markdown at the cursor, rendered everywhere else (Mermaid diagrams, Excalidraw drawings, `transcript` blocks, Obsidian callouts, collapsible `<details>` blocks)
- **Always-on-top floating windows** — `NSPanel`-based sticky notes that stay above all windows (tiling WM friendly)
- **Global hotkeys** — Summon any note instantly from any application
- **Pure `.md` files** — No metadata, no front matter. Full Obsidian / VS Code compatibility
- **Periodic notes** — Date-based file paths with rollover delay and templates
- **Slash command** — Type `/` at line start to insert blocks (Excalidraw diagram, Mermaid diagram, transcript block, table) via a command picker
- **Smart Paste** — Cmd+Shift+V converts URLs, HTML, and JSON to Markdown on paste
- **Image Paste & Resize** — Cmd+V to paste images as PNG; drag the right edge to resize
- **Window Warp** — Modifier+H/J/K/L to snap windows to a 3×3 grid
- **External Editor Sync** — Live file watching; edits in Obsidian or VS Code reflect instantly
- **Per-note styling** — Themes and transparency configured per note; global CSS customization via `--chirami-*` variables
- **CLI** — `chirami display` to show Markdown in a floating window from the terminal; `chirami context` to read the focused note's context as JSON for use with external tools

See [Features](docs/features.md) for the full feature guide and keyboard shortcuts.

## Quick Start

**Prerequisites:** macOS 14.2 or later

**Install via Homebrew:**

```bash
brew install --cask uphy/tap/chirami
```

**Install manually:** Download the latest `Chirami-*-macOS.zip` from [Releases](https://github.com/uphy/chirami/releases), unzip it, and move `Chirami.app` to `~/Applications`.

> **Note:** Chirami is not code-signed. If macOS blocks the app on first launch, run:
> ```bash
> xattr -dr com.apple.quarantine /Applications/Chirami.app
> ```

**Create a minimal config** at `~/.config/chirami/config.yaml`:

```yaml
notes:
  - path: ~/Notes/todo.md
transcript:
  language: ja
  dictionary_file: ~/.config/chirami/transcript-lexicon.yaml
```

Example transcript lexicon:

```yaml
version: 1
terms:
  - text: uphy
    readings: [ユーピー, ユーピーさん]
  - text: Chirami
    readings: チラミ
```

The first time you record a transcript, Chirami downloads the sherpa-onnx model to `~/.local/state/chirami/models/sherpa-onnx/`.
The selected transcript model is stored in `~/.local/state/chirami/state.yaml` and can be changed from the transcript block UI.

Built-in model IDs currently include:

- `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`
- `sherpa-onnx-nemo-parakeet-tdt_ctc-0.6b-ja-35000-int8`

Launch Chirami — it appears as a menu bar icon. Click it to toggle your notes.

See [Getting Started](docs/getting-started.md) for the full setup guide.

## Configuration

Config file: **`~/.config/chirami/config.yaml`**

```yaml
notes:
  - path: ~/Notes/todo.md
    title: TODO
    theme: blue
    hotkey: cmd+shift+t

  - path: ~/Notes/daily/{yyyy-MM-dd}.md
    title: Daily
    theme: green
    hotkey: cmd+shift+d
    rollover_delay: 2h

  - path: ~/Desktop/scratch.md
    hotkey: cmd+shift+s
    position: cursor

transcript:
  language: ja
  dictionary_file: ~/.config/chirami/transcript-lexicon.yaml
  devices:
    mic: default
    system: all
  labels:
    mic: You
    system: Others
```

See [Configuration](docs/configuration.md) for the full field reference.

## Documentation

- [Getting Started](docs/getting-started.md) — Installation through first note display
- [Configuration](docs/configuration.md) — Full config.yaml field reference
- [Features](docs/features.md) — Feature guide and keyboard shortcuts
- [CSS Theming](docs/css-theming.md) — Customize colors, fonts, and themes via CSS variables
- [Advanced](docs/advanced.md) — Periodic Notes, Smart Paste, Images, Transient Note, Karabiner integration
- [Product Vision](docs/product-vision.md) — Why Chirami exists

## Development

**Prerequisites:** macOS 14.2 or later, [mise](https://mise.jdx.dev/)

| Task | Command | Description |
|------|---------|-------------|
| Generate | `mise run generate` | Generate Xcode project via xcodegen |
| Build | `mise run build` | Release build (.app bundle) |
| Install | `mise run apply` | Copy .app to ~/Applications |
| Clean | `mise run clean` | Remove build artifacts |
| Lint | `mise run lint` | Run SwiftLint |
| Lint fix | `mise run lint-fix` | Auto-fix SwiftLint violations |

**Build & install from source:**

```bash
mise run build && mise run apply
```

**Develop with Xcode:**

```bash
xcodegen generate
open Chirami.xcodeproj
# Build and run with Cmd+R
```

## Dependencies

**Swift (SPM)**

| Library | Purpose | License |
|---------|---------|---------|
| [HotKey](https://github.com/soffes/HotKey) | Global hotkeys | MIT |
| [Yams](https://github.com/jpsim/Yams) | YAML parser | MIT |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | On-device transcription | Apache-2.0 |

**JS (editor-web/)**

| Library | Purpose | License |
|---------|---------|---------|
| [CodeMirror 6](https://codemirror.net/) | Live Preview editor engine | MIT |
| [Excalidraw](https://excalidraw.com/) | Diagram editor / renderer | MIT |
| [mermaid](https://mermaid.js.org/) | Mermaid diagram rendering | MIT |
| [turndown](https://github.com/mixmark-io/turndown) | HTML → Markdown conversion (Smart Paste) | MIT |

## License

[MIT](LICENSE)
