# Configuration

Chirami uses two files:

- **`~/.config/chirami/config.yaml`** — User-managed settings (dotfiles-friendly).
- **`~/.local/state/chirami/state.yaml`** — Auto-managed runtime state. No manual editing needed.

## Full Example

```yaml
hotkey: cmd+shift+n

defaults:
  color: yellow
  transparency: 0.9
  font_size: 14
  position: fixed
  auto_hide: false
  attachment:
    dir: ~/Pictures/chirami/

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
    color: blue
    transparency: 0.95
    font_size: 14
    hotkey: cmd+shift+t
    position: fixed
    auto_hide: false

  - path: ~/Notes/daily/{yyyy-MM-dd}.md
    title: Daily
    color: green
    hotkey: cmd+shift+d
    rollover_delay: 2h
    template: ~/Notes/templates/daily.md

  - path: ~/Desktop/scratch.md
    color: yellow
    hotkey: cmd+shift+s
    position: cursor
    auto_hide: true
```

## Top-Level Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `hotkey` | string | — | Global hotkey to toggle all note windows. Format: modifier keys + key (e.g. `cmd+shift+n`). |
| `defaults` | object | — | Default values applied to all notes. Per-note settings override these. |
| `drag_modifier` | string | `command` | Modifier key for window dragging. Allowed: `command`, `option`, `shift`, `control`. |
| `warp_modifier` | string | `ctrl+option` | Modifier key combination for Window Warp (HJKL grid movement). Specify modifiers joined with `+` (e.g. `ctrl+option`, `command+shift`). Allowed tokens: `ctrl`/`control`, `option`/`opt`, `command`/`cmd`, `shift`. |
| `smart_paste` | object | — | Smart Paste configuration. See [Smart Paste](advanced.md#smart-paste). |
| `karabiner` | object | — | Karabiner-Elements integration. See [Karabiner](advanced.md#karabiner-elements-integration). |
| `notes` | array | `[]` | List of note configurations. |

## Defaults

Fields in `defaults` are applied to every note unless the note overrides them.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `color` | string | `yellow` | Background color. |
| `transparency` | number | `0.9` | Window opacity (0.0 = fully transparent, 1.0 = fully opaque). |
| `font_size` | integer | `14` | Font size in points. |
| `position` | string | `fixed` | Window positioning mode. `fixed` or `cursor`. |
| `auto_hide` | boolean | `false` | Hide the window automatically when it loses focus. |
| `attachment.dir` | string | — | Default attachment directory for images. See [Images](advanced.md#images). |

## Note Settings

Each entry in `notes` configures one sticky note window.

| Field | Type | Default | Required | Description |
|-------|------|---------|----------|-------------|
| `path` | string | — | yes | File path. Absolute or `~/` relative. Supports `{date-format}` placeholders for periodic notes. |
| `title` | string | filename | no | Window title shown in the title bar. |
| `color` | string | from defaults | no | Background color: `yellow`, `blue`, `green`, `pink`, `purple`, `gray`. |
| `transparency` | number | from defaults | no | Window opacity (0.0–1.0). |
| `font_size` | integer | from defaults | no | Font size in points. Range: 8–32. |
| `hotkey` | string | — | no | Global hotkey to toggle this note (e.g. `cmd+shift+m`). |
| `position` | string | from defaults | no | `fixed` (remembers last position) or `cursor` (appears at mouse cursor). |
| `auto_hide` | boolean | from defaults | no | Hide window when it loses focus. |
| `rollover_delay` | string | — | no | Delay before date rollover for periodic notes (e.g. `2h`, `30m`). |
| `template` | string | — | no | Template file path for periodic notes. Copied when creating a new day's file. |
| `attachment.dir` | string | — | no | Attachment directory for images. Overrides `defaults.attachment.dir`. See [Images](advanced.md#images). |

### Hotkey Format

Hotkeys are specified as modifier keys joined with `+`, followed by the key:

- Modifiers: `cmd`, `shift`, `option`/`alt`, `control`/`ctrl`
- Examples: `cmd+shift+m`, `cmd+option+n`

### Colors

Six preset colors are available: `yellow`, `blue`, `green`, `pink`, `purple`, `gray`.

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

`~/.local/state/chirami/state.yaml` stores runtime state (window positions, sizes, visibility, always-on-top). Chirami manages this file automatically — there is no need to edit it by hand.

```yaml
windows:
  a1b2c3:
    position: [100, 200]
    size: [300, 400]
    visible: true
    always_on_top: true

bookmarks:
  a1b2c3: <Base64 encoded security-scoped bookmark>
```
