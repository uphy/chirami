---
name: update-docs
description: Update docs/features.md and README.md to reflect code changes
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git diff:*, git log:*)
---

# Update Documentation

Update `docs/features.md` and `README.md` to reflect recent code changes.

## Process

1. Run `git diff` and `git log` to identify what changed
2. Read `docs/features.md` and `README.md`
3. Determine if changes include user-facing features, shortcuts, or behavior changes
4. If so, update the relevant docs to reflect the changes
5. Skip updates for bug fixes, refactoring, internal changes, and test changes that don't affect documented behavior

## Rules

- `docs/features.md`: Full feature guide. Update when features, shortcuts, or behaviors are added, changed, or removed
- `README.md`: High-level overview. Update only for significant new features
- Keep the existing writing style and structure
- Do not rewrite sections that are unaffected by the changes
