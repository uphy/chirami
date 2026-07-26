## Context

Periodic notes are built from three cooperating pieces:

- `PathTemplateResolver.resolve` turns a template like `~/Notes/daily/{yyyy-MM-dd}.md` plus a `Date` into one exact path (`Chirami/Services/PathTemplateResolver.swift`).
- `PeriodicFileNavigator.listMatchingFiles` rescans the directory on every ◀/▶ press and sorts matching relative paths lexicographically (`Chirami/Services/PeriodicFileNavigator.swift`).
- `WindowManager.checkRollover()` runs every 60 seconds, resolves the template at the current logical date, and switches the window if the resolved path differs from the displayed one (`Chirami/Services/WindowManager.swift`).

The first piece and the third assume "1 period = 1 file". For a stream of events (1 answer = 1 file with second-granularity timestamps), the resolved "now" path almost never exists, so `checkRollover()` would create and switch to empty files every minute. The second piece, however, already does exactly what a stream needs. This change adds a mode that keeps the navigator and replaces time-based resolution with latest-file resolution.

**Constraints:**

- Pure Markdown philosophy: no frontmatter, no index/sidecar files. The directory listing *is* the data model.
- External writers are arbitrary processes (shell hooks); Chirami cannot demand a registration API. The file system is the interface.
- Config must stay backward compatible: existing `path` templates keep periodic behavior without edits.

## Goals / Non-Goals

**Goals:**

- 1 event = 1 file: external processes drop Markdown files into a directory; Chirami shows the newest and lets the user flip back with ◀/▶.
- Never interrupt reading: auto-advance only when the user is already at the latest entry.
- Zero writer-side coupling: a writer needs to know only the directory and the filename format.
- Keep periodic notes byte-for-byte unchanged in behavior.

**Non-Goals:**

- Unread tracking, badges, or counts.
- Aggregating multiple directories into one feed.
- Search/filter within a stream.
- A `chirami append`/`chirami add` CLI (covered by the separate `chirami-append` proposal; not needed when producers write files directly).
- Watching for modifications of *non-displayed* files (the existing single-file `FileWatcher` already covers the displayed file).

## Decisions

### 1. Extend periodic notes with a `mode` field rather than adding a new note type

**Chosen:** `mode: periodic | stream` on template-path notes, default `periodic`.

**Why:** stream and periodic share the template-as-match-pattern concept, the navigator, the window, and the hotkey plumbing; they differ only in how "current" is chosen and what triggers automatic switching. A separate note type would duplicate all of the shared behavior and force users to learn a second path syntax. A `mode` enum also leaves room for future variants without another schema change. Validation: `mode: stream` on a path without `{...}` is a config error.

### 2. "Latest" = lexicographic maximum, not filesystem mtime

**Chosen:** the latest file is the last element of the existing lexicographically sorted match list.

**Why:** it reuses `PeriodicFileNavigator`'s ordering exactly, so "latest" is always consistent with what ▶ can reach — there is one ordering, not two. mtime is fragile under `touch`, sync tools, and editors that rewrite files. The trade-off is a **writer contract**: date formats must be zero-padded and fixed-length (e.g. `{yyyy-MM-dd-HHmmss}`) so lexicographic order equals chronological order, and writers should bump to the next second on collision instead of appending a suffix (an unmatched suffix would be invisible to navigation). This contract is documentation, not code.

Stream templates additionally accept a single `*` wildcard in the filename component (e.g. `{yyyy-MM-dd-HHmmss}-*.md`), matching zero or more characters. The concrete driver: users running several Claude Code sessions in parallel want the producing project visible in the filename itself (`2026-07-13-091654-llm-ops.md`), not only inside the note. Ordering stays chronological because the fixed-length timestamp remains the leftmost component; the slug only breaks ties within the same second, which is harmless. `*` is rejected in periodic templates — `PathTemplateResolver.resolve` could not produce a concrete "today" path from it.

### 3. Directory watching via `DispatchSource` on the directory file descriptor

**Chosen:** a new `DirectoryWatcher` service that opens the parent directory FD and listens for `.write` events, debounced (~200 ms), then diffs the match list.

**Why:** it mirrors the existing `FileWatcher` implementation style (single-FD `DispatchSource`), needs no new dependency, and one watcher per stream note is cheap. FSEvents would add recursive watching we don't need — templates with subdirectories (e.g. `{yyyy}/{MM}/{dd-HHmmss}.md`) are resolved against the deepest fixed directory; for the initial release, stream templates are restricted to placeholders in the filename component only, keeping the watcher single-level. Debouncing coalesces bursts (a hook writing header then body, or several files landing together).

### 4. Follow semantics: auto-advance only from the latest file, only while visible

**Chosen:** on new-file detection, switch iff `window.isVisible && displayedFile == previousLatest`. Otherwise refresh navigation button state only.

**Why:** this is the `tail -f` contract users already understand. The alternative — always jump to newest — destroys the primary use case (reading back through history while new events arrive). The other alternative — never auto-advance — makes the visible window silently stale, which contradicts the External Editor Sync promise that what you see is current.

### 5. Rollover timer is skipped entirely for stream notes; `rollover_delay` is ignored

**Chosen:** `checkRollover()` returns early for `mode: stream`; a config warning is logged if `rollover_delay` is set together with `stream`.

**Why:** rollover exists to answer "has the period changed?", a question that has no meaning for event streams. Repurposing the timer as a polling fallback was considered and rejected: the directory watcher covers the same need without a 60-second lag, and two switching mechanisms would race.

### 6. `create` hotkey = quick capture; empty directory = create first entry

**Chosen:** in stream mode, `create` resolves the template at the current time and creates that file (a new latest entry). Opening a stream note whose directory has no matching files does the same.

**Why:** it reuses the exact code path periodic notes use for "today doesn't exist yet", keeps the hotkey meaningful (jot a manual entry into the same stream), and avoids building a special empty-state UI for the initial release. The cost — an occasional empty entry at the head of a brand-new stream — is minor and self-heals as real entries arrive. When the template contains a `*` wildcard, creation resolves it to the empty string (e.g. `{yyyy-MM-dd-HHmmss}-*.md` → `2026-07-13-091654-.md`): slightly ugly, but unambiguous, template-matching, and correctly ordered.

### 7. Always open at latest; do not persist a reading position

**Chosen:** `toggle`/launch always shows the latest file; `state.yaml` is not extended.

**Why:** a stream is a feed — "what's new" is the default question. Persisting a back-position risks reopening onto a stale entry days later with no cue that newer entries exist. Users who want history reach it with ◀, which is one keypress away.

## Risks / Trade-offs

- **Same-second collisions from concurrent writers** produce a next-second bump per the writer contract; two uncoordinated writers could still race `stat`+`write`. Accepted: worst case is one overwritten event, and the primary use case has a single writer.
- **Watcher misses while the app is not running** are inherently fine: latest-resolution happens at open time from the directory listing, not from watch events.
- **Large directories** (years of answers) make each rescan O(n log n) over filenames. Accepted for the initial release; if it becomes measurable, cache the sorted list between watcher events.
