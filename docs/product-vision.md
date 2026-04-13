# Product Vision — Golden Circle

## Why

While you work, you always need something else at hand — a TODO list, a meeting agenda, a scratch pad, a reference document. But every time you switch to another app to check it, you lose your train of thought.

Obsidian offers a great editing experience, but it can't display notes quickly alongside your primary work. Raycast Notes came close, but it isn't file-based and can't share your existing files. Every approach forces you to leave what you were doing.

**Chirami floats what you need above your screen — so you never have to switch away.**

## How

- **Global Hotkeys** — Summon a note instantly without lifting your hands from the keyboard.
- **Sticky-note floating UI** — Always-on-top NSPanel windows stay in front of your workspace. No app switching.
- **Tiling WM coexistence** — NSPanel windows are ignored by tiling window managers like aerospace. Notes float independently without disrupting your tiled layout.
- **Plain `.md` files** — Uses any `.md` file directly. Pure Markdown only — no metadata. Fully compatible with Obsidian, VS Code, and any text editor.
- **Live Preview** — Obsidian-style editing. The block at the cursor shows raw Markdown; everything else is rendered.
- **Any-path registration** — Register files from anywhere: an Obsidian vault, a project's `todo.md`, or any arbitrary path.

## What

A macOS sticky-note Markdown app — a floating companion for your daily work.

Anyone who needs quick access to notes, TODOs, references, or scratch content while working can float them above their screen with a hotkey. Global hotkeys summon floating sticky notes that render and edit Markdown in place. In tiling WM environments like aerospace, notes float independently above your tiled windows.

**In one sentence:** "Float what you need above your screen — without breaking your flow."

## Scope

Chirami is a **floating workspace layer**. File management, organization, and multi-file operations are out of scope.

- Active content creation within panels (writing notes, completing TODOs, capturing thoughts) is in scope.
- File organization (creating new files, renaming, moving) is handled by existing tools like Obsidian or the Finder.
- For scratch notes, use a single fixed file (e.g. `scratch.md`) — write freely and periodically clean it up with another tool.
- What Chirami solves is "keep working, and float what you need above your screen."
