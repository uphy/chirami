# CSS Theming

Chirami uses CSS custom properties (`--chirami-*`) as the public API for customizing note appearance.

## How It Works

On startup, Chirami injects its built-in CSS (`chirami-default.css`) into every note's WebView. This file defines the default `--chirami-*` variables (yellow theme).

You can override any variable by providing your own CSS file via `config.yaml`.

## Configuration

```yaml
# ~/.config/chirami/config.yaml
appearance:
  css_file: ~/.config/chirami/custom.css
  variables:
    font-size: 14px
    font: "JetBrains Mono, monospace"

notes:
  - path: ~/notes/work.md
    title: Work
    theme: blue    # Apply a built-in or custom theme by name
```

Two ways to override variables:

- **`variables`** — quick overrides for a handful of `--chirami-*` properties. Keys without a `--` prefix are treated as `--chirami-<key>`. Applied as inline style on `<html>`, so they win over every stylesheet rule (including theme selectors). Best for one-liner tweaks like font size or family.
- **`css_file`** — a full CSS file when you need media queries (e.g. different colors per dark mode) or custom theme selectors.

## Precedence

From lowest to highest:

1. Built-in defaults (`:root` in `chirami-default.css`)
2. Built-in themes (`[data-chirami-theme="..."]`)
3. User `css_file`
4. `appearance.variables` (inline style on `<html>`)
5. Runtime adjustments from `Cmd+`/`Cmd+-` (also inline; overwrites step 4 for `--chirami-font-size`)

## Public CSS Variables

| Variable | Description |
|---|---|
| `--chirami-bg` | Note background color |
| `--chirami-text` | Primary text color |
| `--chirami-accent` | Interactive / emphasis color |
| `--chirami-muted` | Secondary text color |
| `--chirami-border` | Standard border color |
| `--chirami-surface` | Embedded widget surface (table headers, callouts, chips) — recessed, so mix toward `--chirami-text` |
| `--chirami-surface-strong` | Stronger embedded surface |
| `--chirami-surface-raised` | Raised controls / popovers (slash picker, search panel) — elevated, so mix toward the lighter side |
| `--chirami-code` | Inline code text color |
| `--chirami-code-bg` | Inline code background color |
| `--chirami-selection` | Text selection highlight color |
| `--chirami-danger` | Danger / destructive color |
| `--chirami-warning` | Warning color |
| `--chirami-overlay` | Modal overlay color |
| `--chirami-font` | Font family |
| `--chirami-font-size` | Base font size (e.g. `14px`) |

These variables are stable across minor releases. Any other variables prefixed with `--chirami-` are internal and may change.

## Built-in Themes

The following themes are defined in `chirami-default.css`. Reference them with the `theme` field in `config.yaml`.

| Theme name | Description |
|---|---|
| `yellow` | Default yellow sticky note |
| `blue` | Blue tone |
| `green` | Green tone |
| `pink` | Pink tone |
| `purple` | Purple tone |
| `gray` | Neutral gray |

All built-in themes support both light and dark mode via `@media (prefers-color-scheme: dark)`.

## Customization Examples

### Override the default background color

```css
/* ~/.config/chirami/custom.css */
:root {
  --chirami-bg: #1a1a2e;
  --chirami-text: #eaeaea;
}
```

### Define a custom theme

```css
/* ~/.config/chirami/custom.css */
[data-chirami-theme="monokai"] {
  --chirami-bg: #272822;
  --chirami-text: #f8f8f2;
  --chirami-accent: #66d9e8;
  --chirami-code: #a6e22e;
  --chirami-muted: color-mix(in srgb, var(--chirami-text) 72%, var(--chirami-bg) 28%);
  --chirami-border: color-mix(in srgb, var(--chirami-text) 20%, transparent);
  --chirami-surface: color-mix(in srgb, var(--chirami-bg) 88%, white 12%);
  --chirami-surface-raised: color-mix(in srgb, var(--chirami-bg) 76%, white 24%);
}
```

Then set `theme: monokai` on individual notes in `config.yaml`.

### Font customization

```css
:root {
  --chirami-font: "JetBrains Mono", monospace;
  --chirami-font-size: 13px;
}
```

## Dark Mode

Dark mode is handled automatically by `@media (prefers-color-scheme: dark)` in the CSS. Chirami respects macOS system appearance settings. You can override dark mode values in your custom CSS:

```css
@media (prefers-color-scheme: dark) {
  :root {
    --chirami-bg: #1e1e1e;
    --chirami-text: #d4d4d4;
  }
}
```

## Hot Reload

Edits to `config.yaml` (both `appearance.variables` and `appearance.css_file`) and to the CSS file referenced by `css_file` take effect immediately on every open note window. No app restart is needed.

Changing `appearance.variables.font-size` while the app is running will overwrite any runtime adjustment made via `Cmd+`/`Cmd+-`. Treat config changes as the authoritative value.

## Notes

- Because `appearance.variables` injects an inline style, it also wins over user CSS theme selectors. Leave properties out of `variables` if you want a theme to control them.
- `appearance.variables` values are unconditional (no media query support). For dark-mode-specific overrides, use `css_file`.
