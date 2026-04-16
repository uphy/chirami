## Context

Chirami is a macOS sticky-note Markdown app whose core promise is "float what you need above your screen without breaking your flow." Meeting capture is a natural fit — users already have a floating note open during calls — but currently requires switching to a separate transcription tool.

The existing codebase already solves the closest comparable problem for **Excalidraw**: a Markdown code block that mounts a rich interactive widget via CodeMirror, persists its state inline, and bridges to native Swift for anything beyond JS's reach. The `transcript` block follows the same pattern intentionally so we can reuse known-good infrastructure (`NoteWebView`/`NoteWebViewBridge`, CodeMirror widget lifecycle, `PluginStateStore`) rather than inventing parallel plumbing.

**Technical constraints:**

- **macOS 14.2+ requirement** for Core Audio Process Taps. Earlier versions cannot capture system audio without a virtual audio device (BlackHole/Loopback), which conflicts with Chirami's "zero setup" stance.
- **Apple Silicon** strongly preferred: on-device ASR plus concurrent system-audio capture is still compute-heavy. Intel Macs will technically run but are out of the support target.
- **Plain Markdown philosophy**: output must be greppable plain text usable in Obsidian / VS Code. No JSON blobs, no hidden metadata.
- **Privacy default**: no raw audio is retained; only the transcript text lives on disk.

## Goals / Non-Goals

**Goals:**

- Let the user drop ` ```transcript ` into any note, press one button, and get mic + system audio captured into the same block as `[YYYY-MM-DD HH:MM:SS] You: text` / `[YYYY-MM-DD HH:MM:SS] Others: text` lines.
- Everything runs **on-device**. No network round-trip per utterance; the only network use is a one-time model download.
- Reuse the Excalidraw-style CodeMirror widget + Swift bridge pattern so the codebase's architectural surface area does not grow.
- Keep the block useful even without Chirami: lines are plain Markdown, greppable and editable in any tool.
- Honor a three-tier device-selection fallback (block-local → config → system default) so dotfiles sharing stays meaningful while per-session overrides remain possible.

**Non-Goals:**

- Speaker diarization inside a single audio source (e.g., distinguishing two people in the room speaking into the same mic). Mic-vs-system split is the only speaker granularity.
- Retaining raw audio for re-transcription with a larger model later. The transcript is the artifact.
- Rich inline formatting (partial/unconfirmed chunks in italic, confidence colors, etc.) in the initial release — the block is plain text only.
- Per-block audio-source overrides via code-block info-string attributes (` ```transcript mic=AirPods `). Deferred to a future change.
- Non-Apple-Silicon performance tuning.
- Automatic silence-based stop. The user explicitly presses stop.
- Simultaneous recording across multiple `transcript` blocks. Only one active recording per app.

## Decisions

### 1. Code block name: `transcript` (not `stt`, `voice`, `whisper`)

**Chosen:** `transcript`.

**Why:** it describes what is *inside the block* (the transcribed text), which is consistent with how `excalidraw` describes the diagram data it contains. `stt` is a technical acronym opaque to most readers; `whisper` couples the block's name to its current implementation; `voice` and `speech` are ambiguous (could imply TTS, voice commands, etc.); `dictation` collides with macOS's built-in feature. `transcript` also survives a future engine swap with no rename.

### 2. Speaker labels: `You` / `Others`

**Chosen:** mic audio is labeled `You`, system audio is labeled `Others`. Both are user-overridable via `transcript.labels.mic` and `transcript.labels.system` in `config.yaml`, but the feature ships with hardcoded English defaults because the rest of Chirami's UI is English.

**Why:** matches Otter/Zoom/Meet conventions, is unambiguous in meeting context, renders identically in every editor (no emoji fallback risk), and scales to a future diarization feature where `Others` can be refined into named speakers.

### 3. Markdown output format: `[YYYY-MM-DD HH:MM:SS] Speaker: text`

**Chosen:** each confirmed chunk becomes its own line using `[YYYY-MM-DD HH:MM:SS] Speaker: text`. Timestamps are recorded as wall-clock time at capture, so `Stop → Start` and mixed mic/system confirmation order do not require session-relative reconstruction. Sessions are still separated by a bare `---` line when "追加録音" appends to an existing transcript.

**Why:** This is the dominant convention across commercial transcript tools, so users' existing mental models port over. Line-per-chunk means `grep`, `wc -l`, and diff-friendly edits all work naturally. Session separators let a user record → pause for a break → record again and still know where each session began.

### 4. STT engine: sherpa-onnx, default `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`

**Chosen:** sherpa-onnx with a default model of `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`.

**Alternatives considered:**

- **whisper.cpp**: mature, but would still require custom streaming/session logic in the app.
- **Previous Whisper-based approach**: worked for offline/local inference, but required too much app-side segmentation/deduplication logic for stable realtime behavior in this product.
- **Apple Speech framework (`SFSpeechRecognizer`)**: lower accuracy for long-form Japanese and no streaming for non-dictation use; also pushes audio through Apple's cloud unless on-device mode is available (model-dependent).

sherpa-onnx gives us: an OSS runtime with Swift-callable C API, model distribution we can prefetch/manage ourselves, and a simpler realtime path for Japanese meeting audio than the previous Whisper-based approach.

`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` is the default because it performs materially better in realtime than the previous Whisper-based setup for this app's meeting-capture workflow. Smaller or alternative sherpa-onnx models remain configurable via `config.yaml`.

### 5. Model storage: `~/.local/state/chirami/models/sherpa-onnx/`, downloaded on first use

**Chosen:** auto-download to `~/.local/state/chirami/models/sherpa-onnx/<model-id>/` when the first recording starts and the model is absent. Users may alternatively point `transcript.model` at an absolute path for pre-placed models (dotfiles / air-gapped machines).

**Why not bundle:** even the `small` model (~250MB) dwarfs the rest of the Chirami binary and would drag every release artifact down. Users who never record should never pay the cost.

**Why not `Application Support`:** Chirami already uses `~/.local/state/chirami/` for volatile, machine-local state (see `AppState`). Models fit that category — reproducible from a URL, safe to delete, not part of user configuration.

**Progress UX:** download progress is shown inside the `transcript` block (percent + MB). The user can cancel; cancellation returns the block to Idle.

### 6. System audio capture: Core Audio Process Taps (macOS 14.2+)

**Chosen:** use `CATapDescription` with process filtering. At record start, enumerate processes currently producing audio output (via `AudioObjectGetPropertyData` with `kAudioHardwarePropertyProcessObjectList`) and either (a) tap all active output processes (`system: all`), or (b) tap a user-configured process name, or (c) skip system capture if `system: off`.

**Alternatives considered:**

- **BlackHole / Loopback virtual device**: requires user-side setup (Audio MIDI Setup → multi-output device). Contradicts Chirami's "works immediately" stance.
- **Screen Capture Kit audio**: captures audio tied to screen recording, which pulls in a privacy-heavy permission prompt users will reasonably refuse.

Process taps let us capture *only* the meeting app (Zoom/Meet/Slack Huddle) without picking up Spotify BGM. They require their own user-authorization prompt on first use, but that prompt is scoped to audio capture only.

### 7. Device selection: three-tier fallback

**Chosen:**

1. Block-local override (runtime UI selection, persisted to `state.yaml`).
2. `config.yaml` `transcript.devices.{mic,system}`.
3. macOS system default.

If a more specific tier names a device that's currently unavailable (e.g., AirPods disconnected), we log a warning and fall through to the next tier, surfacing a toast inside the block.

**Why:** matches how people actually work — they configure a preferred mic in dotfiles, but frequently swap headsets mid-day. Auto-fallback beats failing hard with "AirPods not found."

### 8. State machine: Idle / Recording / Paused / Processing / Completed / Error

Strict state transitions:

- `Idle → Recording` on "● 録音開始".
- `Recording ↔ Paused` via "⏸" / "▶".
- `Recording|Paused → Processing → Completed` on "■ 停止" (Processing is the brief window while the speech engine finalizes the trailing audio).
- `Completed → Recording` on "● 追加録音" (prepends `---` session separator).
- Any state `→ Error` on fatal failure (permission denied, model load failure, tap crash). Error has explicit "再試行" back to the previous state.
- `Any → Idle` on "🗑 クリア" (with confirmation).

The state lives in Swift (`TranscriptSession` actor per block). JS widget mirrors it via `transcriptStateChanged` messages and never owns truth.

### 9. Streaming output: confirmed chunks only

**Chosen:** only the engine's confirmed/finalized segments are written to the block. Partial/unconfirmed hypotheses are shown (if at all) only as a single-line live caption inside the widget chrome, never inserted into the Markdown body.

**Why:** writing and then rewriting text in the CodeMirror doc causes cursor jumps and conflict risk if the user is editing other parts of the note. Confirmed-only means every write is append-only and idempotent.

### 10. Editor integration: end-of-block append with user-event tagging

**Chosen:** each confirmed chunk is appended inside the `transcript` block (just before the closing ` ``` `) via `EditorView.dispatch` with `userEvent: "input.transcript"`. This tag lets us exclude transcript-insertions from undo history grouping with user edits, and lets other extensions (spellcheck, autolink) opt out if needed.

**Cursor protection:** if the user's selection is inside the same block, we insert *after* the last existing line and leave the selection untouched. If the user is scrolled away from the block end, we do not auto-scroll.

### 11. Concurrency: one active recording per app

Chirami is a single-user tool and audio devices are exclusive resources. Starting a recording while another block is already recording prompts "停止して新規録音に切り替えますか？". This keeps mental overhead low and avoids device-contention bugs.

### 12. Config shape

```yaml
transcript:
  model: sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17   # model-id or absolute path
  language: ja                            # or "auto"
  devices:
    mic: default                          # "default" | device-name | uniqueID
    system: all                           # "all" | process-name | "off"
  labels:
    mic: You
    system: Others
```

Absent section ⇒ all defaults. Backward compatible with existing configs.

## Risks / Trade-offs

- **Raises minimum macOS to 14.2.** Mitigation: document clearly in README; the rest of Chirami keeps working on older macOS but the `transcript` block surfaces an error state with an explanation.
- **Model download is a cliff in first-run UX**. Mitigation: download happens lazily at first record, progress is visible inside the block, and users can point `transcript.model` at a pre-fetched local path or choose a lighter sherpa-onnx model in config.
- **Core Audio Process Tap permission** is separate from mic permission and will surprise users the first time. Mitigation: show a dedicated pre-prompt inside the block ("Chirami needs permission to listen to another app's audio — this will ask once") before triggering the system dialog.
- **Process targeting is brittle** when meeting apps change names or spawn helper processes. Mitigation: default to `all` (all active output processes) rather than name-matching; `config.yaml` name match is an escape hatch, not the default.
- **Realtime segmentation is still product-sensitive** even with sherpa-onnx. Mitigation: isolate all engine calls behind a `TranscriptionEngine` protocol so swapping models or backends is local.
- **Battery / thermals during long meetings.** Neural Engine inference is efficient but not free; a 90-minute call is non-trivial. Mitigation: show elapsed time prominently; future work can add a low-power mode (smaller model / longer chunk windows).
- **Japanese punctuation quality** varies by model. Mitigation: default to the current SenseVoice model, and surface model tradeoffs in config docs.
- **File-on-disk grows indefinitely** for long meetings if the user never clears. Mitigation: this is no different from any other Markdown note in Chirami and matches user expectations; no special handling.
- **Plain-text output means no partial-confidence markers.** Power users may want to see "this is a rough guess" visually. Mitigation: accept this as a v1 constraint; if demand appears, add a widget-only overlay without changing the Markdown format.

## Migration Plan

Greenfield capability — no migration needed. Shipping steps:

1. Land the speech engine dependency and native runtime wiring (no behavior change on its own).
2. Ship Swift audio + transcription plumbing behind an internal flag; no UI surface yet.
3. Ship the CodeMirror widget + bridge wiring. Existing notes continue to parse `transcript` blocks as plain code blocks until the widget lands.
4. Enable the widget by default once end-to-end flow is verified.
5. No rollback concern: disabling the feature is as simple as removing the CodeMirror extension registration; existing notes keep the plain text they already have.

## Open Questions

- Should "● 追加録音" always insert `---` as the session separator, or should the separator be configurable (e.g., blank line only)?
- When the user explicitly edits a transcript line (fixing a misrecognition), should subsequent "追加録音" visually emphasize the new session start even though timestamps are wall-clock based?
- Do we want any form of keyword highlighting (e.g., bold the speaker's name mentions) at transcript time, or strictly leave all post-processing to the user / downstream tools? Leaning toward the latter for v1.
- Should the `transcript` block widget surface a quick "copy transcript" button, or rely on users selecting the block text manually? Low-cost to add, but easy to defer.
