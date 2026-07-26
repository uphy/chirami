---
title: Advanced
---

# Advanced Features

## Periodic Notes

Periodic Notes are a type of Registered Note that automatically resolve to a date-based file path. Use `{date-format}` placeholders in the `path` field — any path containing `{...}` is treated as a periodic note.

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

## Stream Notes

Stream Notes are a mode for template-path notes built for event streams instead of calendar periods — one event, one file. The typical producer is an external process that drops a Markdown file per event into a directory, such as a Claude Code Stop hook writing each assistant answer (see [AI Integrations](ai-integrations.md)). Rather than resolving to "today's file", a stream note always shows the newest matching file.

Set `mode: stream` on a note whose `path` contains a `{...}` placeholder in the filename component:

```yaml
notes:
  - path: ~/dev/notes/_workspace/claude/{yyyy-MM-dd-HHmmss}-*.md
    title: Claude Answers
    mode: stream
    hotkeys:
      - key: option+c
        action: toggle
      - key: option+shift+c
        action: create
```

The optional `*` wildcard matches any run of characters (including none) in the filename component, so external writers can append a slug — a project name, a session id — to distinguish parallel producers without breaking chronological order (e.g. `2026-07-13-091654-llm-ops.md`). `*` is only valid in `stream` mode; periodic templates reject it.

### Latest-File Resolution

"Current" for a stream note is the lexicographically last file matching the template — not a time-resolved path. The **Today** button periodic notes show becomes **Latest** for stream notes: it jumps to the newest matching file. If no matching file exists yet, Chirami creates one from the template resolved at the current time, same as periodic notes.

### Follow Behavior

The note's parent directory is watched for new matching files. When one appears:

- If the window is visible **and** currently showing the latest file, it auto-advances to the new file — `tail -f` semantics.
- Otherwise, only the ◀/▶ button states are refreshed. You're never yanked away from a file you're reading.

`rollover_delay` has no meaning in stream mode and is ignored (a warning is logged if both are set) — there's no logical date to roll over; the directory watcher is what drives switching.

### Navigation

◀ / ▶ work exactly as in periodic notes: each press rescans the directory and sorts matches lexicographically, so files created by external processes are picked up without restarting Chirami.

### Quick Capture

The `create` hotkey resolves the template at the current time and creates a new file, showing it as the latest entry — useful for jotting a manual note into the same stream.

### Writer Contract

Because "latest" is defined as the lexicographic maximum of filenames, writers must produce names whose sort order matches chronological order:

- Use zero-padded, fixed-length date formats, e.g. `{yyyy-MM-dd-HHmmss}` — not variable-width formats.
- On a filename collision (a write landing in the same second as an existing file), bump the timestamp to the next second. Don't append a suffix like `-2` — a suffix outside the template is invisible to navigation and latest resolution.

## Smart Paste

Cmd+V triggers Smart Paste, which converts clipboard content to Markdown before inserting. Use Cmd+Shift+V for plain text paste.

### Conversion Rules

| Clipboard Content | Result |
|-------------------|--------|
| URL | `[](url)` — cursor placed inside `[]` for quick title entry |
| HTML | Converted to Markdown (headings, lists, links, tables, etc.) |
| JSON | Wrapped in a `` ```json `` code block |
| Multi-line code | Wrapped in a `` ``` `` code block |
| Plain text | Inserted as-is |

Content types are detected in this priority order: URL → HTML → JSON → Code → Plain text.

### Settings

```yaml
smart_paste:
  enabled: true  # Set to false to disable (Cmd+V falls through to normal paste)
```

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

Use `position: cursor` to create a note that appears at the mouse cursor. Cursor notes start unpinned by default — they hide automatically when focus is lost. Useful for scratch-pad or quick-capture workflows.

```yaml
notes:
  - path: ~/Notes/scratch.md
    title: Scratch
    hotkeys:
      - key: option+s
        action: toggle
    position: cursor
```

Press the hotkey → the note pops up at your cursor → type your note → click elsewhere and it vanishes. Click the pin button (📌) to keep it visible.

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

### Delete

Hover over an image to reveal a delete button (×) at the top-right corner. Click the button to remove the image's Markdown link from the note.

- The deletion is undoable (Cmd+Z)
- The image file itself is not deleted immediately — orphaned files are cleaned up on app startup (see [Orphaned Image Cleanup](#orphaned-image-cleanup))

### Resize

Drag the right edge of an image to resize it. The cursor changes to a resize cursor (↔) when hovering near the right edge.

- Drag right to enlarge, left to shrink (minimum width: 50px)
- On release, the final width is written into the Markdown as `![alt|width](url)`
- The resize is undoable (Cmd+Z)

You can also set the width manually in Markdown using `![alt|width](url)` syntax:

```markdown
![screenshot|300](image.png)
```

- A number after `|` sets the display width in pixels
- If the specified width exceeds the window width, the image is scaled down to fit
- Without a width specification, the image fits to the window width

### Attachment Directory

Configure the image storage directory with `attachment.dir`.

```yaml
notes:
  - path: ~/Notes/todo.md
    attachment:
      dir: attachments/
```

**Resolution order:**

1. Per-note `attachment.dir` if set
2. Static notes: `<note-stem>.attachments/` (same directory as the note)
3. Periodic notes: template path's parent directory + `attachments/`

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

## CLI

See [CLI](cli.md) for usage details.

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

Chirami note windows are ignored by tiling window managers like [aerospace](https://github.com/nikitabobko/AeroSpace) by default. Notes float independently without disrupting your tiled layout — no extra configuration needed.
