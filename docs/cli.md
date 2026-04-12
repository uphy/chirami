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
# {"file":"/path/to/note.md","selection":"","line":1,"column":0}

# With text selected in the note
chirami context
# {"file":"/path/to/note.md","selection":"selected text","line":5,"column":3}
```

**Output fields**

| Field | Description |
|-------|-------------|
| `file` | Absolute path to the note file |
| `selection` | Currently selected text (empty string if nothing selected) |
| `line` | Line number of the cursor (1-indexed) |
| `column` | Column of the cursor within the line (0-indexed) |

Returns exit code 1 with `no focused note` on stderr if no note was recently focused.

**Example: pass context to an AI tool**

```bash
chirami context | jq -r '.selection' | claude "Summarize:"
```
