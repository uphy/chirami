## Why

Users frequently attend meetings while using Chirami as a floating scratch pad, and currently have to switch to a separate transcription tool (Otter, macOS Dictation, Zoom's built-in transcript) to capture what was said. This breaks the "float what you need without leaving your flow" philosophy. Introducing an in-note transcription block keeps meeting capture inside the same sticky note the user is already writing in, stored as plain Markdown for full Obsidian compatibility.

## What Changes

- Add a new `transcript` Markdown code block type. Placing ` ```transcript ` in a note renders an inline recording widget (play/pause/stop, device display, level meter) via the existing CodeMirror widget pattern used by `excalidraw` blocks.
- Capture audio from two sources simultaneously: the user's microphone (labeled `You`) and system audio via Core Audio Process Taps (labeled `Others`). Requires macOS 14.2+.
- Run on-device speech-to-text using **WhisperKit** (CoreML). Default model `openai_whisper-large-v3_turbo`, auto-downloaded on first use to `~/.local/state/chirami/models/whisper/`. Manual model paths also supported.
- Stream confirmed transcription chunks into the code block body in the format `[MM:SS] You: text` / `[MM:SS] Others: text`. Text remains plain Markdown — editable, greppable, readable in any editor.
- Extend `config.yaml` with a new `transcript:` section covering model, language, default devices, and speaker labels. No changes to `state.yaml` schema beyond a recent-device cache.
- Add a new `transcript` capability spec documenting the block's lifecycle (Idle → Recording → Paused → Completed → Error), controls, fallback device-selection strategy, and Markdown output format.

## Capabilities

### New Capabilities
- `transcript-block`: In-note speech-to-text capture. Covers the `transcript` code block, recording state machine, device selection fallback, WhisperKit integration, model management, and the plain-text output format.

### Modified Capabilities
<!-- None. This is a greenfield capability; no existing spec's requirements change. -->

## Impact

- **New Swift code**: Audio capture stack (`AVAudioEngine` for mic, `CATapDescription` for system audio), `WhisperKit` integration, streaming transcription manager, device enumeration, permissions flow, per-block session coordinator.
- **New JS code** (`editor-web/`): `transcript` CodeMirror extension (widget, state badge, controls, level meter). New Swift↔JS bridge messages (`transcriptRecordStart`, `transcriptChunk`, `transcriptRecordStop`, `transcriptStateChanged`, `transcriptDevicesRequest`).
- **New dependency**: WhisperKit (Swift Package Manager). Adds ~several MB to the binary; CoreML models are downloaded at runtime, not bundled.
- **Config**: New top-level `transcript:` section in `config.yaml`. Backward compatible — absent section means feature is available but uses built-in defaults.
- **State**: New `~/.local/state/chirami/models/whisper/` directory for downloaded models. New optional entries in `state.yaml` for last-used mic / system-audio process.
- **Entitlements / permissions**: Microphone usage (`NSMicrophoneUsageDescription`) and Core Audio Process Tap authorization. Both prompted on first record, not at app launch.
- **Platform requirement**: Raises minimum macOS target to **14.2** for system-audio capture. Mic-only recording could work on older versions as a fallback, but out of MVP scope.
- **Out of scope for this change**: speaker diarization beyond mic/system split, per-block device overrides via code-block attributes, silence-based auto-stop, retaining raw audio files, non-Apple-Silicon optimization.
