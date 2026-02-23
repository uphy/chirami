# Product Vision — Golden Circle

## Why

You want to jot down a note or check your TODO list while working — but every time, you have to switch to an editor and lose your train of thought.

Obsidian offers a great editing experience, but it can't display notes quickly and unobtrusively alongside your work. Raycast Notes came close, but it isn't Markdown-based and can't share files with Obsidian. Keyboard-only operation also had its limits.

**Fusen exists to let you work with your notes without breaking your flow.**

## How

- **Global Hotkeys** — Summon a note instantly without lifting your hands from the keyboard.
- **Sticky-note floating UI** — Always-on-top NSPanel windows stay in front of your workspace. No app switching.
- **Tiling WM coexistence** — NSPanel windows are ignored by tiling window managers like aerospace. Notes float independently without disrupting your tiled layout.
- **Full Obsidian compatibility** — Uses the same `.md` files directly. Pure Markdown only — no metadata.
- **Live Preview** — Obsidian-style editing. The block at the cursor shows raw Markdown; everything else is rendered.
- **Any-path registration** — Register files from anywhere: an Obsidian vault, a project's `todo.md`, or any arbitrary path.

## What

A macOS sticky-note Markdown app.

Developers and engineers who manage notes in Obsidian can check, write, and complete TODOs without interrupting their work. Global hotkeys summon floating sticky notes that render and edit Markdown in place. Because Fusen uses the same files as Obsidian, it introduces zero friction to your existing workflow. In tiling WM environments like aerospace, notes float independently above your tiled windows.

**In one sentence:** "Access your Obsidian notes as sticky notes — without breaking your flow."

## Scope

Fusen is strictly a **display and access layer**. File creation, deletion, and organization are out of scope.

- Note management (creating new notes, organizing information) is handled by existing tools like Obsidian.
- For scratch notes, use a single fixed file (e.g. `scratch.md`) — write freely and periodically clean it up with another tool.
- What Fusen solves is "quickly access that file and read or write without stopping your work."
