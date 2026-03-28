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

## Usage

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

## Options

| Flag | Description |
|------|-------------|
| `--file <path>` | Path to a Markdown file to display (editable) |
| `--wait` | Block until the window is closed |
