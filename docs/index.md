---
layout: home

hero:
  name: Chirami
  text: Sticky-note Markdown for macOS
  tagline: Access your notes as floating windows — without breaking your flow.
  image:
    src: /logo.png
    alt: Chirami
  actions:
    - theme: brand
      text: Get Started
      link: /getting-started
    - theme: alt
      text: View on GitHub
      link: https://github.com/uphy/chirami

features:
  - icon: ⚡
    title: Instant Access
    details: Global hotkeys summon any note instantly from any application. No app switching, no context loss.
  - icon: 📝
    title: Markdown Live Preview
    details: Obsidian-style editing — raw Markdown at the cursor, rendered everywhere else.
  - icon: 🔗
    title: Full Obsidian Compatibility
    details: Pure .md files with no metadata or front matter. Works seamlessly with Obsidian, VS Code, and any text editor.
  - icon: 📌
    title: Always-on-top Windows
    details: Floating windows that stay above all apps. Ignored by tiling window managers like AeroSpace — no extra configuration needed.
  - icon: 📅
    title: Periodic Notes
    details: Date-based file paths with rollover delay and templates. Compatible with Obsidian Daily Notes.
  - icon: 🖥️
    title: CLI Integration
    details: chirami display pipes Markdown output from any terminal command into a floating window.
---

## Install

```bash
brew install --cask uphy/tap/chirami
```

Or download the latest release from [GitHub Releases](https://github.com/uphy/chirami/releases).

> **Note:** Chirami is not code-signed. If macOS blocks the app on first launch, run:
> ```bash
> xattr -dr com.apple.quarantine ~/Applications/Chirami.app
> ```

## Minimal Setup

Create `~/.config/chirami/config.yaml`:

```yaml
notes:
  - path: ~/Notes/todo.md
    hotkey: cmd+shift+t
```

Launch Chirami from the menu bar. Press `Cmd+Shift+T` to toggle your note.

## Why Chirami?

You want to check your TODO list or jot down a note while working — but every time you switch to an editor, you lose your train of thought.

Obsidian offers a great editing experience but can't display notes quickly and unobtrusively alongside your work. **Chirami exists to let you work with your notes without breaking your flow.**

> *Chirami* — from the Japanese *ちら見*, meaning "a quick glance."
