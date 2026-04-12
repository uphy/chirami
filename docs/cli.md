---
title: CLI
---

# CLI

The `chirami` CLI opens Markdown content as a floating window from the terminal.

## Install

The CLI binary is bundled inside `Chirami.app`. Add it to your PATH:

```bash
export PATH="$PATH:~/Applications/Chirami.app/Contents/MacOS"
```

## Commands

### display

Opens Markdown content in a floating window.

```bash
# Show inline text
chirami display "## Meeting Notes"

# Open a file for editing
chirami display --file ~/project/TODO.md

# Pipe command output
git diff --stat | chirami display

# Wait for the window to close before continuing
chirami display --wait --file ~/Notes/scratch.md
```

**Content sources** (priority order): positional argument > `--file` > stdin.

- Positional argument and stdin content are read-only.
- `--file` opens the file for editing.
- `--wait` blocks the CLI process until the window is closed.

**Options**

| Flag | Description |
|------|-------------|
| `--file <path>` | Path to a Markdown file to display (editable) |
| `--wait` | Block until the window is closed |

### context

Outputs the context of the last focused Registered Note as JSON.

```bash
chirami context
# {"file":"/path/to/note.md","selection":{"text":"","from":{"line":1,"column":0},"to":{"line":1,"column":0}},"cursor":{"line":1,"column":0}}

# With text selected in the note
chirami context
# {"file":"/path/to/note.md","selection":{"text":"selected text","from":{"line":5,"column":0},"to":{"line":5,"column":13}},"cursor":{"line":5,"column":13}}
```

**Output fields**

| Field | Description |
|-------|-------------|
| `file` | Absolute path to the note file |
| `selection.text` | Currently selected text (empty string if nothing selected) |
| `selection.from` | Start position of the selection `{ line, column }` |
| `selection.to` | End position of the selection `{ line, column }` |
| `cursor` | Cursor position `{ line, column }` |

`line` is 1-indexed; `column` is 0-indexed. When nothing is selected, `selection.from` and `selection.to` equal `cursor`.

Returns exit code 1 with `no focused note` on stderr if no note was recently focused.

**Example: pass context to an AI tool**

```bash
chirami context | jq -r '.selection.text' | claude "Summarize:"
```
