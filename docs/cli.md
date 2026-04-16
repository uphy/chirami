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

# Include the resolved transcript block text
chirami context --transcript
# {"file":"/path/to/note.md","selection":{"text":"","from":{"line":42,"column":0},"to":{"line":42,"column":0}},"cursor":{"line":42,"column":0},"transcript":{"text":"[2026-04-16 14:03:10] Others: ...","truncated":false}}
```

**Output fields**

| Field | Description |
|-------|-------------|
| `file` | Absolute path to the note file |
| `selection.text` | Currently selected text (empty string if nothing selected) |
| `selection.from` | Start position of the selection `{ line, column }` |
| `selection.to` | End position of the selection `{ line, column }` |
| `cursor` | Cursor position `{ line, column }` |
| `transcript` | Transcript excerpt when one of the transcript flags is used. `null` if no transcript block is available. |

`line` is 1-indexed; `column` is 0-indexed. When nothing is selected, `selection.from` and `selection.to` equal `cursor`.

Returns exit code 1 with `no focused note` on stderr if no note was recently focused.

When transcript options are used, Chirami resolves a single `transcript` code block with this priority:

1. The block containing the current selection
2. The block containing the cursor
3. The last `transcript` block in the note

**Transcript options**

| Flag | Description |
|------|-------------|
| `--transcript` | Include the full text of the resolved `transcript` block |
| `--transcript-last <n>` | Include only the last `n` transcript utterances |
| `--transcript-seconds <n>` | Include only utterances from the last `n` seconds |

`--transcript`, `--transcript-last`, and `--transcript-seconds` are mutually exclusive. Filtered transcript output includes `transcript.truncated: true` only when the returned text is a subset of the full block text.

**Example: pass context to an AI tool**

```bash
chirami context | jq -r '.selection.text' | claude "Summarize:"

# Feed only the latest transcript turns to an LLM
chirami context --transcript-last 8 | jq -r '.transcript.text' | claude "Clarify the latest question:"
```

For more advanced integrations (Raycast script command, Claude Code skill), see [AI Integrations](/ai-integrations).
