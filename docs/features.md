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

**Always on Top** — Note windows float above all other windows by default. Toggle via the right-click context menu.

**Dragging** — Hold the drag modifier key (default: Cmd) and drag anywhere in the note window to move it. The modifier can be changed with `drag_modifier` in config.yaml.

**Color** — Right-click the note and pick a color from the context menu. Six presets: yellow, blue, green, pink, purple, gray.

**Transparency** — Configured per note in config.yaml (`transparency: 0.0–1.0`).

**Pin** — Notes with `auto_hide: true` show a pin button (📌) at the right end of the title bar. Click to temporarily suspend auto-hide for the session. While pinned, the note stays visible even when focus moves to another window. Click again to unpin and restore normal auto-hide behavior. Pin state is not persisted — it resets when the note is closed.

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

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+L | Toggle task list on current line |
| Cmd+B | Bold selection (`**text**`) |
| Cmd+I | Italic selection (`*text*`) |
| Cmd+F | Open find bar |
| Cmd+= / Cmd++ | Increase font size |
| Cmd+- | Decrease font size |
| Cmd+Shift+V | Smart Paste |
| Tab (on list item) | Indent list item |
| Shift+Tab (on list item) | Dedent list item |
| Tab (with selection) | Indent all selected lines |
| Shift+Tab (with selection) | Dedent all selected lines |
| Enter (on list item) | Continue list with next marker |
| Enter (on empty list item) | End list |
| Ctrl+A | Move cursor to content start (press again for line start) |
| ESC / Cmd+W | Close note |
| Ctrl+Option+H / Ctrl+Option+← | Warp window left |
| Ctrl+Option+L / Ctrl+Option+→ | Warp window right |
| Ctrl+Option+K / Ctrl+Option+↑ | Warp window up |
| Ctrl+Option+J / Ctrl+Option+↓ | Warp window down |

Per-note and global hotkeys (configured in config.yaml) toggle note visibility from any application.

## Menu Bar

Chirami lives in the macOS menu bar. Click the icon to open the popover:

- **Note list** — Each note is shown with its color indicator and title. Click to toggle visibility. A checkmark indicates the note is currently visible.
- **Show All / Hide All** — Toggle all notes at once.
- **Edit Config** — Open `~/.config/chirami/config.yaml` in your default editor.
- **Launch at Login** — Toggle auto-launch on macOS startup.
- **Quit Chirami** — Exit the application.

## External Editor Sync

Chirami watches note files for changes using `DispatchSource`. Edits made in Obsidian, VS Code, or any other editor are reflected immediately in the Chirami window.
