---
title: Getting Started
---

# Getting Started

## Requirements

- macOS 14.0 (Sonoma) or later

## Install

**Via Homebrew (recommended):**

```bash
brew install --cask uphy/tap/chirami
```

**Manual install:** Download the latest `Chirami-*-macOS.zip` from [Releases](https://github.com/uphy/chirami/releases), unzip it, and move `Chirami.app` to `~/Applications`.

> **Note:** Chirami is not code-signed. If macOS blocks the app on first launch, run:
> ```bash
> xattr -dr com.apple.quarantine ~/Applications/Chirami.app
> ```

## Minimal Configuration

Create `~/.config/chirami/config.yaml`:

```yaml
notes:
  - path: ~/Notes/todo.md
    hotkey: cmd+shift+t
```

That's it. Press `Cmd+Shift+T` to toggle the note from any application.

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
