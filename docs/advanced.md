# Advanced Features

## Periodic Notes

Periodic notes automatically resolve to a date-based file path. Use `{date-format}` placeholders in the `path` field — any path containing `{...}` is treated as a periodic note.

### Template Syntax

Placeholders use [DateFormatter](https://developer.apple.com/documentation/foundation/dateformatter) patterns:

| Pattern | Output | Example |
|---------|--------|---------|
| `yyyy` | 4-digit year | 2026 |
| `MM` | 2-digit month | 02 |
| `dd` | 2-digit day | 23 |
| `EEEE` | Full weekday name | Monday |

**Path examples:**

```yaml
# Single-level daily notes
path: ~/Notes/daily/{yyyy-MM-dd}.md
# → ~/Notes/daily/2026-02-23.md

# Nested year/month/day
path: ~/Notes/{yyyy}/{MM}/{dd}.md
# → ~/Notes/2026/02/23.md
```

### Rollover Delay

For late-night work sessions, `rollover_delay` shifts the logical date boundary past midnight.

```yaml
notes:
  - path: ~/Notes/daily/{yyyy-MM-dd}.md
    rollover_delay: 2h
```

With `rollover_delay: 2h`, at 1:30 AM the note still resolves to yesterday's date. The rollover happens at 2:00 AM instead of midnight.

**Format:** `Nh` (hours) or `Nm` (minutes) — e.g. `2h`, `30m`.

### Template File

When a periodic note's file doesn't exist yet, Chirami creates it automatically. If `template` is specified, the template file is copied as the initial content:

```yaml
notes:
  - path: ~/Notes/daily/{yyyy-MM-dd}.md
    template: ~/Notes/templates/daily.md
```

Without `template`, an empty file is created.

### Navigation

Periodic notes show navigation controls in the title bar:

- **◀ / ▶** — Navigate to the previous or next existing file matching the template pattern.
- **Today** — Jump to the current logical date (respecting `rollover_delay`).

A background timer checks every 60 seconds whether the logical date has changed. If you're viewing "today" and the date rolls over, the note automatically switches to the new day's file. The same switch also happens when a hidden window is shown — if the date changed while the window was hidden, it opens to today's note.

## Smart Paste

Cmd+Shift+V triggers Smart Paste, which converts clipboard content to Markdown before inserting.

### Conversion Rules

| Clipboard Content | Result |
|-------------------|--------|
| URL | `[page title](url)` (title fetched asynchronously) |
| HTML | Converted to Markdown (headings, lists, links, tables, etc.) |
| JSON | Wrapped in a `` ```json `` code block |
| Multi-line code | Wrapped in a `` ``` `` code block |
| Plain text | Inserted as-is |

Content types are detected in this priority order: HTML → URL → JSON → Code → Plain text.

### Settings

```yaml
smart_paste:
  enabled: true         # Set to false to disable (Cmd+Shift+V falls through to normal paste)
  fetch_url_title: true  # Set to false to skip title fetching for URLs
```

When `fetch_url_title` is enabled, Chirami inserts `[](url)` immediately, then replaces the empty title with the fetched page title (from `og:title` or `<title>` tag) within a 5-second timeout.

## Karabiner-Elements Integration

Chirami can set a [Karabiner-Elements](https://karabiner-elements.pqrs.org/) variable when a note window gains or loses focus. This lets you define Karabiner key remappings that only apply while editing a Chirami note.

### Chirami Config

```yaml
karabiner:
  variable: chirami_active
  on_focus: 1
  on_unfocus: 0
```

### Karabiner-Side Condition

In your Karabiner rule, add a condition to match the variable:

```json
{
  "type": "variable_if",
  "name": "chirami_active",
  "value": 1
}
```

This lets you, for example, remap keys for Markdown editing only while a Chirami window is focused.

The `cli_path` field is optional — Chirami auto-detects the `karabiner_cli` binary location. Set it explicitly if the binary is in a non-standard location.

## Transient Note

Combine `position: cursor` with `auto_hide: true` to create a note that appears at the mouse cursor and disappears when you click away. Useful for scratch-pad or quick-capture workflows.

```yaml
notes:
  - path: ~/Notes/scratch.md
    title: Scratch
    hotkey: cmd+shift+s
    position: cursor
    auto_hide: true
```

Press the hotkey → the note pops up at your cursor → type your note → click elsewhere and it vanishes.

## Images

### Image Paste

Paste an image from the clipboard (Cmd+V) to save it as a PNG file and insert a Markdown image link.

```
![](attachments/image-a1b2c3d4.png)
```

**Details:**

- If the clipboard contains both text and an image, text takes priority (normal paste)
- File names are generated from the SHA256 hash of the image content (`image-<hash>.png`)
- Pasting the same image multiple times reuses the existing file (no duplicates)
- The link is inserted as a relative path from the note file

### Display

Images are scaled to fit the window width.

- By default, images stretch to the full window width (minus left/right margins)
- Aspect ratio is preserved
- Maximum height is capped at 400px

### Width Specification

Use `![alt|width](url)` syntax to specify the display width in pixels.

```markdown
![screenshot|300](image.png)
```

- A number after `|` sets the display width in pixels
- If the specified width exceeds the window width, the image is scaled down to fit
- Without a width specification, the image fits to the window width

### Attachment Directory

Configure the image storage directory with `attachment.dir`.

```yaml
defaults:
  attachment:
    dir: ~/Pictures/chirami/

notes:
  - path: ~/Notes/todo.md
    attachment:
      dir: attachments/
```

**Resolution order:**

1. Per-note `attachment.dir` if set
2. `defaults.attachment.dir` if set
3. Static notes: `<note-stem>.attachments/` (same directory as the note)
4. Periodic notes: template path's parent directory + `attachments/`

**Path formats:**

| Path | Resolves to |
|------|-------------|
| `~/Pictures/chirami/` | Expanded from home directory |
| `/absolute/path/` | Used as-is |
| `attachments/` | Relative to the note's parent directory |

### Orphaned Image Cleanup

On app startup, Chirami automatically deletes image files that are no longer referenced by any note.

- Runs in the background without affecting startup speed
- Only targets files matching the `image-*.png` pattern
- Scans the Markdown content of all notes to identify referenced images
- For periodic notes, checks image references across all files matching the template pattern

## Tips

### Dotfiles Management

`config.yaml` lives at `~/.config/chirami/config.yaml` — a standard XDG path. Symlink or include it in your dotfiles repository. `state.yaml` is stored separately at `~/.local/state/chirami/state.yaml` and should not be version-controlled.

### Obsidian Daily Notes Compatibility

Point a periodic note's `path` to the same directory Obsidian uses for Daily Notes. Both tools work on the same plain `.md` files with no conflicts:

```yaml
notes:
  - path: ~/Obsidian/Vault/Daily/{yyyy-MM-dd}.md
    title: Daily
    rollover_delay: 2h
    template: ~/Obsidian/Vault/Templates/Daily.md
```

### Tiling Window Manager Coexistence

Chirami uses `NSPanel` windows, which tiling window managers like [aerospace](https://github.com/nikitabobko/AeroSpace) ignore by default. Chirami notes float independently without disrupting your tiled layout — no extra configuration needed.
