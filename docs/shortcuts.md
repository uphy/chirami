---
title: Keyboard Shortcuts
---

# Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+L | Toggle task list on current line (inside a blockquote the task goes after `> `; headings are left unchanged) |
| Cmd+B | Bold selection (`**text**`); again on bold text removes it |
| Cmd+I | Italic selection (`*text*`); again on italic text removes it |
| Cmd+F | Open find bar |
| Cmd+= / Cmd++ | Increase font size |
| Cmd+- | Decrease font size |
| Ctrl+Option+= / Ctrl+Option++ | Scale window up |
| Ctrl+Option+- | Scale window down |
| Cmd+V | Smart Paste |
| Cmd+Shift+V | Plain text paste |
| Tab (on list item) | Indent list item together with its children |
| Shift+Tab (on list item) | Dedent list item together with its children |
| Tab (with selection) | Indent all selected lines |
| Shift+Tab (with selection) | Dedent all selected lines |
| Enter (on list item) | Continue list with next marker |
| Enter (on empty list item) | End list |
| Shift+Enter (on list item) | Line break inside the item (continuation line) |
| Enter (on empty `> ` line) | End the blockquote (one level) |
| Tab / Shift+Tab (raw table row) | Move to next / previous cell (Tab on the last cell appends a row) |
| Option+↑ / Option+↓ (on list item) | Move the item with its children above / below its sibling |
| Tab / Shift+Tab (editing table cell) | Move to next / previous cell (Tab on last cell appends a row) |
| Enter (editing table cell) | Move to cell below |
| Escape (editing table cell) | Discard cell edit |
| Cmd+[ | Fold block at cursor |
| Cmd+] | Unfold block at cursor |
| Cmd+Shift+[ | Fold all blocks |
| Cmd+Shift+] | Unfold all blocks |
| Cmd+Enter (on link) | Open link or bare URL at caret |
| Option+Enter (on link) | Open link or bare URL at caret |
| Ctrl+A | Move cursor to content start (press again for line start) |
| Ctrl+K | Delete to end of line and copy it to the clipboard (consecutive Ctrl+K accumulate), so Cmd+V / Ctrl+Y pastes it back |
| Option+← / Option+→ | Move by word; Japanese text moves by word (今日 / は / 会議) |
| ESC / Cmd+W | Close note (ESC first cancels IME composition, closes the slash command menu / find bar, or clears the selection) |
| Cmd+Option+P | Toggle pin (keep visible when focus moves away) |
| Ctrl+Option+H / Ctrl+Option+← | Warp window left |
| Ctrl+Option+L / Ctrl+Option+→ | Warp window right |
| Ctrl+Option+K / Ctrl+Option+↑ | Warp window up |
| Ctrl+Option+J / Ctrl+Option+↓ | Warp window down |

The default window-warp modifier shown above is configurable via `warp_modifier` in `config.yaml`; the same modifier also applies to window scaling with `=` / `-`. Display-edge gaps are configurable via `warp_margin`.

Per-note and global hotkeys (configured in `config.yaml` via `hotkeys`) can toggle note visibility from any application.
