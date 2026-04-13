# Spec: Product Vision

## Purpose

This spec governs the content and positioning expressed in product-facing documents (`docs/product-vision.md`, `docs/index.md`, `README.md`). It ensures that the vision, messaging, and scope statements are consistent with Chirami's approved positioning as a daily work companion — not just a tool for Obsidian users.

## Requirements

### Requirement: Why section captures the core value of floating overlay

`docs/product-vision.md` の Why セクション SHALL 「作業中に必要なものをウィンドウの上に浮かせて同時に使える」という本質的な価値を述べること。

#### Scenario: Why conveys the overlay value

- **WHEN** reading the Why section of `docs/product-vision.md`
- **THEN** it SHALL describe the pain of context switching away from primary work
- **THEN** it SHALL describe Chirami's solution as floating panels that coexist with primary work (not replacing the view)

#### Scenario: Obsidian is mentioned as example not as core target

- **WHEN** reading the Why section of `docs/product-vision.md`
- **THEN** Obsidian MAY be mentioned as a concrete example
- **THEN** it SHALL NOT be the sole framing of the target user

### Requirement: What section positions Chirami as daily work companion

`docs/product-vision.md` の What セクション SHALL Chiramiを「付箋UIで日々の業務を支えるコンパニオン」として定義すること。

#### Scenario: What covers beyond Obsidian users

- **WHEN** reading the What section of `docs/product-vision.md`
- **THEN** the target user description SHALL NOT be limited to Obsidian users only
- **THEN** it SHALL describe the floating sticky note UI as the core delivery mechanism

### Requirement: Scope section updated for Phase 2

`docs/product-vision.md` の Scope セクション SHALL「strictly a display and access layer」という制約表現を含まないこと。

#### Scenario: Scope allows active content creation within panels

- **WHEN** reading the Scope section of `docs/product-vision.md`
- **THEN** it SHALL NOT say Chirami is "strictly a display and access layer"
- **THEN** it SHALL maintain that file management and organization are out of scope

### Requirement: README reflects expanded positioning

`README.md` の冒頭 SHALL 「付箋UIで日々の業務を支えるコンパニオン」というポジショニングを伝えること。

#### Scenario: tagline is not limited to Obsidian

- **WHEN** reading the opening lines of `README.md`
- **THEN** the description SHALL NOT position Chirami exclusively as a tool for Obsidian users

### Requirement: Approved positioning language is used consistently

以下の文言を各ファイルで使用すること。

#### Scenario: hero text matches approved copy

- **WHEN** reading `docs/index.md` hero section
- **THEN** `text` SHALL be `A floating workspace for your daily work`
- **THEN** `tagline` SHALL be `Float what you need. Keep your focus.`

#### Scenario: Why statement matches approved copy

- **WHEN** reading the Why section of `docs/index.md` and `README.md`
- **THEN** it SHALL use the copy: `While you work, you always need something else at hand. Chirami floats it above your screen.`
