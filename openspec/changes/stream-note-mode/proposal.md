## Why

External processes increasingly produce discrete Markdown "events" that users want to flip through later — the first concrete consumer is a Claude Code Stop hook that writes each assistant answer as `~/dev/notes/_workspace/claude/{yyyy-MM-dd-HHmmss}.md`, so the user can summon a floating note with a hotkey when an answer is too complex for the terminal (Mermaid diagrams, tables, long code blocks) and flip back through previous answers with ◀/▶.

Periodic notes almost support this today: ◀/▶ navigation already rescans the directory on every press and sorts matches lexicographically, so externally created files are picked up without restart. What breaks is the notion of "current": it is strictly resolved from the current wall-clock time (`PathTemplateResolver.resolve`), and the 60-second rollover timer keeps forcing the window back to that resolved path. With fine-grained timestamps (1 event = 1 file), the "now" file almost never exists, so the timer would perpetually switch to — and create — empty files. Periodic notes are designed for "1 period = 1 file"; this change adds the missing "1 event = 1 file" semantics.

## What Changes

- Add an optional `mode` field (`periodic` | `stream`, default `periodic`) to registered notes whose `path` contains a `{...}` template placeholder. Existing configs are unaffected.
- In stream mode, "current" resolves to the **lexicographically last matching file** instead of the template resolved at the current time. The Today button becomes **Latest**.
- The rollover timer does not apply to stream notes (`rollover_delay` is ignored). Instead, the parent directory is watched; when a new matching file appears:
  - if the window is visible **and** currently showing the latest file, it auto-advances to the new file (follow semantics, like `tail -f`);
  - otherwise only navigation button states are refreshed — the user is never yanked away while reading history.
- ◀/▶ navigation is unchanged (rescan + lexicographic sort).
- The per-note `create` hotkey in stream mode creates a new file from the template resolved at the current time (quick-capture semantics); `toggle` shows/hides the window at the latest file.
- Stream templates may include a single `*` wildcard in the filename component (e.g. `{yyyy-MM-dd-HHmmss}-*.md`), matching any run of characters including the empty string. This lets writers append a human-readable slug — project name, session — that distinguishes parallel producers in file listings. Periodic templates do not accept `*`.
- Fallbacks: if the displayed file is deleted, navigate to the latest remaining file; if no matching file exists at open time, create one from the template (same as periodic behavior today).
- Document the writer contract: stream templates must use zero-padded, fixed-length date formats so lexicographic order equals chronological order, and writers should bump to the next second on filename collision.

## Capabilities

### New Capabilities
- `stream-note`: Stream mode for template-path notes. Covers the `mode` config field and validation, latest-file resolution, directory watching with follow semantics, rollover exemption, hotkey behavior, and deletion/empty-directory fallbacks.

### Modified Capabilities
<!-- None. No existing spec covers periodic notes; periodic behavior is unchanged. -->

## Impact

- **Swift**: `ConfigModels` (new `mode` field + validation), `NoteWindow` (current-file resolution branch, Latest button label, follow handling), `WindowManager` (skip `checkRollover()` for stream notes), new `DirectoryWatcher` service alongside the existing single-file `FileWatcher`.
- **Config**: new optional `mode` key; backward compatible — absent means `periodic`.
- **No JS/editor-web changes**: rendering (Mermaid, tables, code blocks) is untouched.
- **Docs**: `docs/configuration.md` (Note Settings table), `docs/advanced.md` (new Stream Notes section), `docs/ai-integrations.md` (Claude Code Stop hook example).
- **Out of scope**: unread badges or counts, cross-note aggregated feeds, filtering/search within a stream, and the `chirami append` CLI (separate proposal; unnecessary here since producers write files directly).
