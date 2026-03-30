---
title: Configuration
---

# Configuration

Chirami uses two files:

- **`~/.config/chirami/config.yaml`** — User-managed settings (dotfiles-friendly).
- **`~/.local/state/chirami/state.yaml`** — Auto-managed runtime state. No manual editing needed.

## Full Example

```yaml
appearance: auto

launch_at_login: true

hotkey: cmd+shift+n

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

color_schemes:
  monokai:
    dark:
      background: [0.149, 0.157, 0.129]
      text: [0.973, 0.973, 0.949]
      link: [0.400, 0.851, 0.937]
      code: [0.663, 0.882, 0.071]
    light:
      background: [0.980, 0.976, 0.965]
      text: [0.149, 0.157, 0.129]
      link: [0.157, 0.451, 0.702]
      code: [0.400, 0.553, 0.031]

notes:
  - path: ~/Notes/todo.md
    title: TODO
    color_scheme: blue
    transparency: 0.95
    font_size: 14
    hotkey: cmd+shift+t
    position: fixed

  - path: ~/Notes/daily/{yyyy-MM-dd}.md
    title: Daily
    color_scheme: green
    hotkey: cmd+shift+d
    rollover_delay: 2h
    template: ~/Notes/templates/daily.md

  - path: ~/Desktop/scratch.md
    color_scheme: yellow
    hotkey: cmd+shift+s
    position: cursor
```

## Top-Level Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `appearance` | string | `auto` | Appearance mode. `auto` (follow system), `light`, or `dark`. |
| `launch_at_login` | bool | `false` | Launch Chirami automatically on macOS login. |
| `show_menu_bar_icon` | bool | `true` | Show the Chirami icon in the macOS menu bar. Set to `false` to hide it (use global hotkey to access notes). |
| `hotkey` | string | — | Global hotkey to toggle all note windows. Format: modifier keys + key (e.g. `cmd+shift+n`). |
| `drag_modifier` | string | `command` | Modifier key for window dragging. Allowed: `command`, `option`, `shift`, `control`. |
| `warp_modifier` | string | `ctrl+option` | Modifier key combination for Window Warp (HJKL grid movement). Specify modifiers joined with `+` (e.g. `ctrl+option`, `command+shift`). Allowed tokens: `ctrl`/`control`, `option`/`opt`, `command`/`cmd`, `shift`. |
| `smart_paste` | object | — | Smart Paste configuration. See [Smart Paste](advanced.md#smart-paste). |
| `karabiner` | object | — | Karabiner-Elements integration. See [Karabiner](advanced.md#karabiner-elements-integration). |
| `color_schemes` | object | — | Custom color scheme definitions. See [Custom Color Schemes](#custom-color-schemes). |
| `notes` | array | `[]` | List of Registered Note configurations. |

## Note Settings (Registered Notes)

Each entry in `notes` configures one Registered Note — a sticky note window managed by Chirami.

| Field | Type | Default | Required | Description |
|-------|------|---------|----------|-------------|
| `path` | string | — | yes | File path. Absolute or `~/` relative. Supports `{date-format}` placeholders for periodic notes. |
| `title` | string | filename | no | Window title shown in the title bar. |
| `color_scheme` | string | `yellow` | no | Color scheme name. Built-in: `yellow`, `blue`, `green`, `pink`, `purple`, `gray`. Custom color schemes defined in `color_schemes` are also accepted. |
| `transparency` | number | `0.9` | no | Window opacity (0.0–1.0). |
| `font_size` | integer | `14` | no | Font size in points. Range: 8–32. |
| `hotkey` | string | — | no | Global hotkey to toggle this note (e.g. `cmd+shift+m`). |
| `position` | string | `fixed` | no | `fixed` (remembers last position) or `cursor` (appears at mouse cursor). |
| `always_on_top` | boolean | `true` | no | Whether the note window floats above all other windows. |
| `rollover_delay` | string | — | no | Delay before date rollover for periodic notes (e.g. `2h`, `30m`). |
| `template` | string | — | no | Template file path for periodic notes. Copied when creating a new day's file. |
| `attachment.dir` | string | — | no | Attachment directory for images. See [Images](advanced.md#images). |

### Hotkey Format

Hotkeys are specified as modifier keys joined with `+`, followed by the key:

- Modifiers: `cmd`, `shift`, `option`/`alt`, `control`/`ctrl`
- Examples: `cmd+shift+m`, `cmd+option+n`

### Built-in Color Schemes

Six built-in color schemes are available: `yellow`, `blue`, `green`, `pink`, `purple`, `gray`.

## Custom Color Schemes

Define custom color schemes in the `color_schemes` block. Each color scheme requires `dark` and `light` variants, each with four color channels as RGB arrays (0.0–1.0).

```yaml
color_schemes:
  monokai:
    dark:
      background: [0.149, 0.157, 0.129]
      text: [0.973, 0.973, 0.949]
      link: [0.400, 0.851, 0.937]
      code: [0.663, 0.882, 0.071]
    light:
      background: [0.980, 0.976, 0.965]
      text: [0.149, 0.157, 0.129]
      link: [0.157, 0.451, 0.702]
      code: [0.400, 0.553, 0.031]

notes:
  - path: ~/Notes/daily/{yyyy-MM-dd}.md
    color_scheme: monokai
```

| Field | Description |
|-------|-------------|
| `background` | Window and editor background color |
| `text` | Body text color |
| `link` | Hyperlink color |
| `code` | Inline code and code block text color |

Custom color scheme names can also override built-in ones (e.g. redefining `yellow`). Changes to `color_schemes` in config.yaml take effect immediately without restarting.

## Smart Paste

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `smart_paste.enabled` | boolean | `true` | Enable Smart Paste (Cmd+Shift+V). |
| `smart_paste.fetch_url_title` | boolean | `true` | Fetch page title when pasting URLs. |

## Karabiner

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `karabiner.variable` | string | — | Karabiner variable name to set on focus/unfocus. |
| `karabiner.on_focus` | int or string | — | Value to set when a Chirami window gains focus. |
| `karabiner.on_unfocus` | int or string | — | Value to set when a Chirami window loses focus. |
| `karabiner.cli_path` | string | auto-detected | Path to `karabiner_cli` binary. |

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
