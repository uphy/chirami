---
title: Features
---

# Features

## Markdown Live Preview

Chirami renders Markdown in an Obsidian-style Live Preview: the block containing the cursor shows raw Markdown, while all other blocks are rendered.

**Supported syntax:**

- Headings (H1–H6)
- **Bold** (`**text**`, `__text__`)
- *Italic* (`*text*`, `_text_`)
- ~~Strikethrough~~ (`~~text~~`)
- Inline code (`` `code` ``)
- Links (`[text](url)`) — clickable
- Images (`![alt](url)`) — rendered inline, fits to window width. See [Images](advanced.md#images).
- Unordered lists (`-`, `*`)
- Ordered lists (`1.`, `2.`)
- Task lists (`- [ ]`, `- [x]`) — clickable checkboxes
- Nested lists
- Blockquotes (`>`)
- Code blocks with syntax highlighting (triple backticks with optional language)
- Tables (GitHub Flavored Markdown pipe syntax)
- Thematic breaks (`---`, `***`, `___`)

## Window Operations

**Always on Top** — Note windows float above all other windows by default. Set `always_on_top: false` in config.yaml to disable.

**Dragging** — Hold the drag modifier key (default: Cmd) and drag anywhere in the note window to move it. The modifier can be changed with `drag_modifier` in config.yaml.

**Color** — Configured per note in config.yaml (`color: yellow/blue/green/pink/purple/gray`).

**Transparency** — Configured per note in config.yaml (`transparency: 0.0–1.0`).

**Pin** — All notes show a pin button (📌) at the right end of the title bar. While pinned, the note stays visible even when focus moves to another window. Unpinned notes hide automatically when they lose focus. Pin state is persisted in state.yaml across restarts. Default: `cursor` notes start unpinned, `fixed` notes start pinned. Shortcut: **Cmd+Option+P**.

**Window Warp** — While a note window is focused, press the warp modifier key (default: Ctrl+Option) + H/J/K/L or the arrow keys to instantly move the window to one of 9 positions in a 3×3 grid. The grid covers the screen with an 8pt margin at each edge. Movement wraps around at the edges — pressing H (or ←) at the left column jumps to the right column of the same row. The current grid position is inferred from the window's actual position, so warp works naturally after manual dragging. In multi-monitor setups, the window warps within the screen it currently occupies. Warp position is persisted across restarts. The modifier key is configurable via `warp_modifier` in `config.yaml`.

## Editor Features

**Task list toggle** — Cmd+L converts the current line to/from a task list item (`- [ ]`). Click a checkbox to toggle it.

**List auto-continuation** — Press Enter on a list item to continue the list with the next marker. Press Enter on an empty list item to end the list.

**Text surround** — Select text and type a bracket or quote character to wrap the selection. Supported pairs:

- `*`, `_`, `` ` ``, `~` (wrap with same character)
- `(`, `[`, `{` (wrap with matching close bracket)
- `"`, `'` (wrap with same quote)

**Indent / Dedent** — Press Tab on a list item line to indent it (adds one level). Press Shift+Tab to dedent. With multiple lines selected, Tab and Shift+Tab indent or dedent all selected lines at once. Tab and Shift+Tab on non-list lines behave normally.

**Image Paste** — Paste an image from the clipboard (Cmd+V) to save it as a PNG file and insert a Markdown image link. See [Images](advanced.md#images).

**Find** — Cmd+F opens the find bar.

**Font size** — Cmd+= / Cmd+- to increase or decrease the font size (range: 8–32).

**Link click** — Click a rendered link to open it in the default browser.

**Link open from caret** — Place the cursor inside a markdown link and press Cmd+Enter or Option+Enter to open the URL in the default browser. Works in both regular text and task list items.

## Keyboard Shortcuts

See [Keyboard Shortcuts](shortcuts.md) for the full reference.

## Menu Bar

Chirami lives in the macOS menu bar. Click the icon to open the popover:

- **Note list** — Each note is shown with its color indicator and title. Click to toggle visibility. A checkmark indicates the note is currently visible.
- **Show All / Hide All** — Toggle all notes at once.
- **Edit Config** — Open `~/.config/chirami/config.yaml` in your default editor.
- **Launch at Login** — Toggle auto-launch on macOS startup.
- **Quit Chirami** — Exit the application.

## CLI

See [CLI](cli.md) for usage details.

## External Editor Sync

Chirami watches note files for changes. Edits made in Obsidian, VS Code, or any other editor are reflected immediately in the Chirami window.
