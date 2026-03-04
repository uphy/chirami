## ADDED Requirements

### Requirement: Collapsible sections and lists
The editor SHALL support folding (collapsing) of sections (headings H1–H6) and lists (bullet, numbered, TODO lists). When a block is folded, its child content SHALL be hidden from view.

#### Scenario: Fold a heading section
- **WHEN** user clicks the fold toggle button on a heading line
- **THEN** the heading's child content (all content until the next heading of equal or higher level) SHALL be hidden

#### Scenario: Fold a list
- **WHEN** user clicks the fold toggle button on a top-level list item
- **THEN** the list item's child items SHALL be hidden

#### Scenario: Unfold a folded block
- **WHEN** user clicks the fold toggle button on a folded block
- **THEN** the block's previously hidden content SHALL be restored to view

### Requirement: Fold indicator on collapsed blocks
The editor SHALL display a `>` character in the left margin of the last visible line of any folded block.

#### Scenario: Indicator displayed for folded section
- **WHEN** a section is folded
- **THEN** a `>` indicator SHALL appear to the left of the heading line

#### Scenario: No indicator for expanded blocks
- **WHEN** a block is expanded (not folded)
- **THEN** no `>` indicator SHALL appear for that block

### Requirement: Fold toggle button on hover/cursor
The editor SHALL display a fold toggle button (chevron icon) to the left of a foldable block's first line when the cursor is on that block. The icon SHALL reflect the current fold state (pointing down when expanded, pointing right when collapsed).

#### Scenario: Toggle button appears on cursor entry
- **WHEN** the cursor moves to a line that is the start of a foldable block
- **THEN** a chevron toggle button SHALL appear to the left of that line

#### Scenario: Toggle button disappears on cursor exit
- **WHEN** the cursor moves away from a foldable block's start line
- **THEN** the toggle button for that block SHALL be hidden

#### Scenario: Chevron direction reflects fold state
- **WHEN** a block is expanded and the toggle button is visible
- **THEN** the chevron SHALL point downward (▾)
- **WHEN** a block is folded and the toggle button is visible
- **THEN** the chevron SHALL point rightward (▸)

### Requirement: Fold state persistence
The fold state of each note SHALL be persisted to state.yaml and restored when the note is reopened.

#### Scenario: Fold state survives app restart
- **WHEN** the user folds a block and restarts the app
- **THEN** the same block SHALL still be folded when the note is reopened

#### Scenario: Stale fold state is discarded
- **WHEN** a note file is modified externally such that a previously folded block no longer exists at the stored line number
- **THEN** the stale fold state entry SHALL be silently discarded and the block SHALL appear expanded

#### Scenario: Periodic Note starts fresh each day
- **WHEN** a Periodic Note resolves to a new file path (e.g., a new day's note)
- **THEN** the note SHALL open with no blocks folded (fold state is keyed by resolved path, so each day's file is independent)
