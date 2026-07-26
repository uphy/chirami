## ADDED Requirements

### Requirement: Built-in CSS is always loaded
The app SHALL bundle a default CSS file that defines `--chirami-*` CSS variables for both light and dark modes using `@media (prefers-color-scheme: dark)`. This CSS is loaded automatically without any user configuration.

#### Scenario: App loads with no user CSS configured
- **WHEN** the app starts with no `appearance.cssFile` in `config.yaml`
- **THEN** the built-in CSS is applied and the note renders with default styling

#### Scenario: Dark mode is active
- **WHEN** macOS dark mode is enabled
- **THEN** the WebView applies the `@media (prefers-color-scheme: dark)` rules from the built-in CSS automatically

### Requirement: User can specify a global CSS file
The app SHALL support an optional `appearance.cssFile` field in `config.yaml` that specifies a path to a user-provided CSS file. The user CSS is loaded after the built-in CSS, allowing any property to be overridden.

#### Scenario: Valid cssFile is specified
- **WHEN** `appearance.cssFile` points to an existing CSS file
- **THEN** both the built-in CSS and the user CSS are applied, with user CSS taking precedence on conflicts

#### Scenario: cssFile path does not exist
- **WHEN** `appearance.cssFile` points to a non-existent file
- **THEN** the app logs a warning and falls back to built-in CSS only, without crashing

#### Scenario: cssFile is omitted
- **WHEN** `appearance.cssFile` is not set in `config.yaml`
- **THEN** only the built-in CSS is applied

### Requirement: Per-note theme name is injected as HTML attribute
The app SHALL support an optional `theme` field per note in `config.yaml`. When set, the value is injected as `data-chirami-theme="<name>"` on the `<html>` element of that note's WebView, allowing CSS to apply theme-specific variable overrides.

#### Scenario: Note has a theme configured
- **WHEN** a note has `theme: monokai` in `config.yaml`
- **THEN** the note's WebView `<html>` element has `data-chirami-theme="monokai"`

#### Scenario: Note has no theme configured
- **WHEN** a note has no `theme` field in `config.yaml`
- **THEN** no `data-chirami-theme` attribute is added to `<html>`

#### Scenario: Built-in theme is referenced
- **WHEN** a note specifies a theme name that is defined in the built-in CSS
- **THEN** the theme's variable overrides are applied to that note

#### Scenario: User-defined theme is referenced
- **WHEN** a note specifies a theme name defined only in the user CSS
- **THEN** the theme's variable overrides are applied to that note

### Requirement: chirami-* CSS variables are the public customization API
The `--chirami-*` CSS variables defined in the built-in CSS SHALL be the stable public API for user customization. Users can override these variables in their CSS file to customize the note appearance.

#### Scenario: User overrides a chirami variable
- **WHEN** user CSS sets `--chirami-bg: #1a1a2e` in `:root`
- **THEN** the note background uses the overridden value

#### Scenario: User overrides a variable for a specific theme
- **WHEN** user CSS sets `[data-chirami-theme="yellow"] { --chirami-bg: #fffde7; }`
- **THEN** notes with `theme: yellow` use that background color

### Requirement: Legacy appearance fields are gracefully ignored
The app SHALL log a warning and ignore `colorScheme`, `font`, and `fontSize` fields if they appear in `config.yaml`, without crashing.

#### Scenario: Old config.yaml with colorScheme field
- **WHEN** `config.yaml` contains a `colorScheme` field
- **THEN** the app starts normally, logs a warning, and applies default CSS styling
