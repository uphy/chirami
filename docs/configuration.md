---
title: Configuration
---

# Configuration

Chirami uses two files:

- **`~/.config/chirami/config.yaml`** — User-managed settings (dotfiles-friendly).
- **`~/.local/state/chirami/state.yaml`** — Auto-managed runtime state. No manual editing needed.

## Full Example

```yaml
appearance:
  mode: auto
  css_file: ~/.config/chirami/custom.css
  variables:
    font-size: 14px
    font: '"JetBrains Mono", monospace'

launch_at_login: true

hotkeys:
  - key: option+n
    action: toggle

drag_modifier: command
warp_modifier: ctrl+option

smart_paste:
  enabled: true
  fetch_url_title: true

karabiner:
  variable: chirami_active
  on_focus: 1
  on_unfocus: 0
  cli_path: /Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli

notes:
  - path: ~/Notes/todo.md
    title: TODO
    theme: blue
    transparency: 0.95
    hotkeys:
      - key: option+t
        action: toggle
    position: fixed

  - path: ~/Notes/daily/{yyyy-MM-dd}.md
    title: Daily
    theme: green
    hotkeys:
      - key: option+d
        action: toggle
      - key: option+shift+d
        action: create
    rollover_delay: 2h
    template: ~/Notes/templates/daily.md

  - path: ~/Desktop/scratch.md
    theme: yellow
    hotkeys:
      - key: option+s
        action: toggle
    position: cursor
```

## Top-Level Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `appearance` | string or object | `auto` | Appearance configuration. Accepts the legacy string form (`auto` / `light` / `dark`) or an object with `mode`, `css_file`, and `variables`. See [Appearance](#appearance). |
| `launch_at_login` | bool | `false` | Launch Chirami automatically on macOS login. |
| `show_menu_bar_icon` | bool | `true` | Show the Chirami icon in the macOS menu bar. Set to `false` to hide it (use global hotkey to access notes). |
| `hotkeys` | array | — | Global hotkey bindings. Top-level supports `toggle` only. |
| `drag_modifier` | string | `command` | Modifier key for window dragging. Allowed: `command`, `option`, `shift`, `control`. |
| `warp_modifier` | string | `ctrl+option` | Modifier key combination for window manipulation shortcuts. It applies to Window Warp (`H`/`J`/`K`/`L` or arrow keys) and window scaling (`=` / `-`). Specify modifiers joined with `+` (e.g. `ctrl+option`, `command+shift`). Allowed tokens: `ctrl`/`control`, `option`/`opt`, `command`/`cmd`, `shift`. If this conflicts with built-in `Cmd+=` / `Cmd+-`, the font shortcuts win. |
| `smart_paste` | object | — | Smart Paste configuration. See [Smart Paste](advanced.md#smart-paste). |
| `karabiner` | object | — | Karabiner-Elements integration. See [Karabiner](advanced.md#karabiner-elements-integration). |
| `notes` | array | `[]` | List of Registered Note configurations. |

## Note Settings (Registered Notes)

Each entry in `notes` configures one Registered Note — a sticky note window managed by Chirami.

| Field | Type | Default | Required | Description |
|-------|------|---------|----------|-------------|
| `path` | string | — | yes | File path. Absolute or `~/` relative. Supports `{date-format}` placeholders for periodic notes. |
| `title` | string | filename | no | Window title shown in the title bar. |
| `theme` | string | — | no | Theme name, applied to the note via the `data-chirami-theme` attribute. Built-in: `yellow`, `blue`, `green`, `pink`, `purple`, `gray`. Custom themes defined in `appearance.css_file` are also accepted. See [CSS Theming](css-theming.md). |
| `transparency` | number | `0.9` | no | Window opacity (0.0–1.0). |
| `hotkeys` | array | `[]` | no | Hotkey bindings for this note. Registered Notes support `toggle` and `create`. |
| `position` | string | `fixed` | no | `fixed` (remembers last position) or `cursor` (appears at mouse cursor). |
| `always_on_top` | boolean | `true` | no | Whether the note window floats above all other windows. |
| `rollover_delay` | string | — | no | Delay before date rollover for periodic notes (e.g. `2h`, `30m`). |
| `template` | string | — | no | Template file path for periodic notes. Copied when creating a new day's file. |
| `attachment.dir` | string | — | no | Attachment directory for images. See [Images](advanced.md#images). |

### Hotkey Format

Hotkeys are configured as an array of bindings:

```yaml
hotkeys:
  - key: option+m
    action: toggle
```

`key` uses modifier keys joined with `+`, followed by the key:

- Modifiers: `cmd`, `shift`, `option`/`alt`, `control`/`ctrl`
- Examples: `option+m`, `option+shift+m`, `option+n`

`action` values:

- `toggle` — show/hide the target note or note group
- `create` — Registered Note only. Ensures the file exists and opens the current resolved note

Recommended pattern:

- Base shortcut for `toggle`
- Same shortcut + `shift` for `create`
- Example: `option+m` = `toggle`, `option+shift+m` = `create`

## Appearance

The `appearance` field configures global display mode and CSS-based theming.

```yaml
appearance:
  mode: auto                          # auto | light | dark
  css_file: ~/.config/chirami/custom.css
  variables:
    font-size: 14px
    font: '"JetBrains Mono", monospace'
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mode` | string | `auto` | Appearance mode: `auto` (follow system), `light`, or `dark`. |
| `css_file` | string | — | Path to a user CSS file layered on top of the built-in styles. Supports `~/` expansion. |
| `variables` | object | — | Quick overrides for `--chirami-*` CSS custom properties. Keys without a `--` prefix are treated as `--chirami-<key>`. Injected as inline style on `<html>`, so these win over every stylesheet rule. |

Six built-in themes are available via the per-note `theme` field: `yellow`, `blue`, `green`, `pink`, `purple`, `gray`.

Changes to `appearance.variables`, `appearance.css_file`, and the CSS file it references are hot-reloaded — no restart needed.

See [CSS Theming](css-theming.md) for the full list of `--chirami-*` variables, how to define custom themes, and dark-mode handling.

## Excalidraw

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `excalidraw.libraries` | string[] | `[]` | Paths to `.excalidrawlib` files to load as read-only libraries in the Excalidraw editor. Both version 1 and version 2 formats are supported. Paths support `~` expansion. |

Example:

```yaml
excalidraw:
  libraries:
    - ~/.config/chirami/excalidraw/system-design.excalidrawlib
    - ~/.config/chirami/excalidraw/aws-icons.excalidrawlib
```

Libraries from [libraries.excalidraw.com](https://libraries.excalidraw.com/) can be downloaded as `.excalidrawlib` files and placed here.

## Smart Paste

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `smart_paste.enabled` | boolean | `true` | Enable Smart Paste (Cmd+Shift+V). |

## Karabiner

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `karabiner.variable` | string | — | Karabiner variable name to set on focus/unfocus. |
| `karabiner.on_focus` | int or string | — | Value to set when a Chirami window gains focus. |
| `karabiner.on_unfocus` | int or string | — | Value to set when a Chirami window loses focus. |
| `karabiner.cli_path` | string | auto-detected | Path to `karabiner_cli` binary. |

## Transcript

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `transcript.engine` | string | `sherpa-onnx` | Speech-to-text engine identifier. |
| `transcript.language` | string | `auto` | Preferred recognition language. |
| `transcript.dictionary_file` | string | — | Optional transcript lexicon file. Chirami loads the listed terms, passes their `readings` (or `text` when `readings` is empty) to STT hotwords, and returns the resolved absolute path plus loaded terms in `chirami context --transcript*`. Relative paths are resolved from `~/.config/chirami/`. `readings` accepts either a single string or a string array. |
| `transcript.devices.mic` | string | `default` | Preferred microphone input. |
| `transcript.devices.system` | string | `all` | Preferred system-audio capture source. |
| `transcript.labels.mic` | string | `You` | Speaker label for microphone transcript lines. |
| `transcript.labels.system` | string | `Others` | Speaker label for system-audio transcript lines. |

Example:

```yaml
transcript:
  language: ja
  dictionary_file: ./transcript-lexicon.yaml
  devices:
    mic: default
    system: all
  labels:
    mic: You
    system: Others
```

Lexicon file format:

```yaml
version: 1
terms:
  - text: uphy
    readings: [ユーピー, ユーピーさん]
  - text: Chirami
    readings: チラミ
  - text: OpenSpec
```

Use `readings` for the way a term is actually spoken. `readings` can be either a single string or an array. Chirami passes every normalized entry in `readings` into STT hotwords when present and falls back to `text` otherwise. The selected sherpa-onnx model may still limit how much effect hotwords have. `text` stays available for downstream LLM-based normalization via `chirami context --transcript*`.

## state.yaml

`~/.local/state/chirami/state.yaml` stores runtime state (window positions, sizes, visibility). Chirami manages this file automatically — there is no need to edit it by hand.

```yaml
windows:
  a1b2c3:
    position: [100, 200]
    size: [300, 400]
    visible: true

bookmarks:
  a1b2c3: <Base64 encoded security-scoped bookmark>
```
