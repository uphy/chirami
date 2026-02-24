# Getting Started

## Prerequisites

- macOS 14.0 (Sonoma) or later
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [mise](https://mise.jdx.dev/) (recommended) or Xcode

## Build & Install

**Using mise (recommended):**

```bash
mise run build && mise run apply
```

This builds a Release `.app` bundle and installs it to `~/Applications`.

**Using Xcode:**

```bash
cd /path/to/chirami
xcodegen generate
open Chirami.xcodeproj
```

Build and run with Cmd+R. SPM dependencies are resolved automatically on first build.

## Minimal Configuration

Create `~/.config/chirami/config.yaml`:

```yaml
notes:
  - path: ~/Notes/todo.md
```

That's it. Chirami will display the file as a floating sticky note.

## Basic Usage

1. **Launch** — Chirami appears as a menu bar icon (note icon in the macOS menu bar).
2. **Show/hide notes** — Click the menu bar icon and select a note to toggle its visibility.
3. **Edit** — Click inside the note window and start typing. Changes are saved automatically.
4. **Add notes** — Edit `config.yaml` directly to add notes (open it via "Edit Config" in the popover).
5. **Edit config** — Click "Edit Config" in the menu bar popover to open `config.yaml` in your default editor. Chirami reloads it automatically.

## Using with Obsidian

Chirami works with plain `.md` files — no metadata, no front matter. Point a note's `path` to any file inside your Obsidian vault:

```yaml
notes:
  - path: ~/Obsidian/Vault/Daily/todo.md
    title: TODO
    color: blue
```

- Chirami watches the file for external changes, so edits made in Obsidian appear instantly.
- Edits made in Chirami are written directly to the file, so Obsidian picks them up on its next refresh.
- No lock conflicts — both apps operate on the same file independently.
