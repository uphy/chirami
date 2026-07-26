---
title: AI Integrations
---

# AI Integrations

`chirami context` outputs the focused note's file path, selection, and cursor position as JSON.
Combined with AI tools, you can edit notes without ever leaving your flow.

## [Raycast Script Command](https://github.com/raycast/script-commands)

Enter a prompt in Raycast and Claude edits the focused note directly — no window switching required.

```bash
#!/bin/bash -l

# @raycast.schemaVersion 1
# @raycast.title Edit Chirami Note
# @raycast.mode fullOutput
# @raycast.icon ✏️
# @raycast.packageName Chirami
# @raycast.description Edit the focused Chirami note with a custom prompt
# @raycast.argument1 { "type": "text", "placeholder": "Prompt (e.g. 'Fix typos')" }

export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

PROMPT="$1"

if [ -z "$PROMPT" ]; then
  echo "No prompt provided"
  exit 1
fi

# Get context from the focused Chirami note
CONTEXT_JSON=$(chirami context 2>/dev/null)
if [ $? -ne 0 ]; then
  echo "No focused note (is Chirami running?)"
  exit 1
fi

# Extract file path from JSON
FILE=$(echo "$CONTEXT_JSON" | jq -r '.file // empty')
if [ -z "$FILE" ]; then
  echo "Failed to get note file path"
  exit 1
fi

# Check file exists
if [ ! -f "$FILE" ]; then
  echo "File not found: $FILE"
  exit 1
fi

# Let Claude edit the file based on the prompt
if ! claude -p "$PROMPT

# Chirami context
$CONTEXT_JSON" \
  --allowed-tools "Edit($FILE)" \
  --add-dir "$(dirname "$FILE")" \
  --permission-mode acceptEdits \
  --output-format text \
  --no-session-persistence; then
  echo "Failed"
  exit 1
fi

echo "Done: $(basename "$FILE")"
```

The full context JSON — file path, selection range, and cursor position — is embedded directly in the prompt so Claude understands exactly where you are in the note. `--allowed-tools "Edit($FILE)"` restricts edits to that file only, so nothing outside the note can be touched.

## Claude Code Skill (chirami-edit)

A [Claude Code skill](https://docs.anthropic.com/en/docs/claude-code/skills) that edits the focused note from within a Claude Code session.
Create `.claude/skills/chirami-edit/SKILL.md` in your project with the following content:

```markdown
---
name: chirami-edit
description: Edit the currently focused Chirami note using `chirami context`. Use this skill whenever
  the user wants to edit, rewrite, fix, or transform the note currently displayed in Chirami — phrased
  as "edit the chirami note", "fix the selected text", "rewrite this section", or any instruction that
  targets the active Chirami note or its selection.
---

# Chirami Note Editor

Edit the currently focused Chirami note based on the user's instruction.

## Steps

1. Run `chirami context` with the Bash tool to get the current note context
2. If it fails (exit code 1 / stderr "no focused note"), stop and tell the user no note is focused
3. Parse the JSON output to get the file path and selection
4. Read the file with the Read tool
5. Apply the user's instruction with the Edit tool

## Context output format

{
  "file": "/path/to/note.md",
  "selection": {
    "text": "selected text, or empty string if nothing selected",
    "from": { "line": 1, "column": 0 },
    "to":   { "line": 2, "column": 5 }
  },
  "cursor": { "line": 1, "column": 0 }
}

## Editing scope

- `selection.text` is non-empty → apply the instruction to the selected text only; leave everything else untouched
- `selection.text` is empty → apply the instruction to the whole file

## Rules

- Make only the changes the user asked for — no extra cleanup, reformatting, or rewrites
- Preserve Markdown syntax and document structure
- Do not add or remove content beyond what the instruction requires
```

Once the file is in place, Claude Code picks up the skill automatically. Just describe what you want:

```
Translate the selected text to English
Fix any typos in the note
Turn the selected bullet list into a table
```

Unlike the Raycast approach, you can keep the conversation going and refine the result interactively.

## Claude Code Stop Hook (Stream Note)

A [Stop hook](https://docs.claude.com/en/docs/claude-code/hooks) fires whenever Claude Code finishes responding. Writing each assistant answer to its own timestamped Markdown file turns your Claude Code history into a [Stream Note](advanced.md#stream-notes) — summon the latest answer with a hotkey when it's too complex for the terminal (Mermaid diagrams, tables, long code blocks), and flip back through previous answers with ◀/▶.

### Hook Script

`~/.claude/hooks/chirami-stream-note.sh` reads the Stop hook's JSON payload from stdin, extracts the transcript path, and writes the last assistant message to a new file:

```bash
#!/bin/bash
set -euo pipefail

DIR="$HOME/dev/notes/_workspace/claude"
mkdir -p "$DIR"

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')

# Concatenate the text blocks of the last assistant message in the transcript
TEXT=$(jq -rs '
  [.[] | select(.type == "assistant")] | last
  | .message.content
  | map(select(.type == "text") | .text)
  | join("\n")
' "$TRANSCRIPT")

[ -z "$TEXT" ] && exit 0

# Writer contract: zero-padded, fixed-length timestamp so lexicographic
# order equals chronological order.
TS=$(date +%Y-%m-%d-%H%M%S)
FILE="$DIR/${TS}.md"

# On collision, bump to the next second instead of appending a suffix
# (an unmatched suffix would be invisible to Chirami's navigation).
while [ -e "$FILE" ]; do
  TS=$(date -j -v+1S -f "%Y-%m-%d-%H%M%S" "$TS" +%Y-%m-%d-%H%M%S)
  FILE="$DIR/${TS}.md"
done

printf '%s\n' "$TEXT" > "$FILE"
```

Make it executable: `chmod +x ~/.claude/hooks/chirami-stream-note.sh`.

### Claude Code Settings

Register the hook in `.claude/settings.json` (project) or `~/.claude/settings.json` (user):

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/chirami-stream-note.sh"
          }
        ]
      }
    ]
  }
}
```

### Chirami Config

Register the directory as a stream note and bind a hotkey to jump straight to the latest answer:

```yaml
notes:
  - path: ~/dev/notes/_workspace/claude/{yyyy-MM-dd-HHmmss}.md
    title: Claude Answers
    mode: stream
    hotkeys:
      - key: option+c
        action: toggle
```

Press `option+c` any time to open the newest answer, and ◀/▶ to flip back through earlier ones — no restart needed even though the files are written by a process outside Chirami.
