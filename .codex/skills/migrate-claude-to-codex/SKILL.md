---
name: migrate-claude-to-codex
description: Migrate Claude Code project artifacts into Codex-native assets. Use when Codex needs to translate `CLAUDE.md`, `.claude/rules/**`, `.claude/skills/**`, `.claude/agents/**`, `.claude/commands/**`, or related Claude settings into `.codex/skills/**`, `agents/openai.yaml`, repo documentation, and Codex-compatible delegation guidance.
---

Convert Claude Code customization into Codex-native instructions and skills.

Start by inventorying the source artifacts:

```bash
find . -maxdepth 3 \
  \( -name 'CLAUDE.md' -o -path '*/.claude/*' \) \
  | sort
```

If the repository already contains both `.claude/skills/*` and `.codex/skills/*`, diff the paired skills first. Reuse the repo's existing Codex style instead of inventing a new one.

Read [references/mapping.md](./references/mapping.md) before editing when any of these are present:
- `.claude/agents/**`
- `.claude/commands/**`
- `.claude/settings*.json`
- hooks or permission allowlists

## Workflow

1. Inventory the Claude assets

   Read these files when present:
   - `CLAUDE.md`
   - `.claude/rules/**`
   - `.claude/skills/**/SKILL.md`
   - `.claude/agents/**`
   - `.claude/commands/**/*.md`
   - `.claude/settings.json` and `.claude/settings.local.json`

2. Classify each piece of information

   Separate the content into:
   - durable project context
   - path- or stack-specific engineering rules
   - reusable workflows
   - delegated specialist prompts
   - permissions, hooks, and local automation

3. Convert `CLAUDE.md`

   Move stable, repo-specific knowledge into one of these targets:
   - an existing Codex skill
   - a new project skill under `.codex/skills/`
   - a `references/` file linked from that skill
   - normal repo docs when the content is user-facing rather than agent-facing

   Do not copy `CLAUDE.md` wholesale into a skill. Keep only the parts another Codex instance would not infer from the codebase quickly.

4. Convert `.claude/rules/**`

   Preserve scope. When a rule is limited to `editor-web/**` or `swift/**`, keep that file-path targeting visible in the new Codex skill description and body.

   Prefer one of these patterns:
   - merge the rule into an existing Codex skill that already owns that area
   - create a focused Codex skill for that area when the rule set is substantial
   - move purely informational rule content into a reference file if it is too detailed for `SKILL.md`

5. Convert `.claude/skills/**`

   Claude and Codex skills are close enough that this is usually a structured rewrite, not a redesign:
   - keep the folder name unless the trigger needs to change
   - reduce frontmatter to `name` and `description` only
   - keep the body imperative and procedural
   - remove Claude-only tool names and rewrite them to Codex-native behavior
   - add `agents/openai.yaml`

   Replace Claude-specific instructions mechanically:
   - `AskUserQuestion` -> ask the user directly with a concise plain-text question only when necessary
   - `TodoWrite` -> use `update_plan` for multi-step work, otherwise just execute
   - `Task` or custom subagents -> convert to a normal skill first; use `spawn_agent` only when the user explicitly asks for delegation

6. Convert `.claude/agents/**`

   Claude custom subagents do not map 1:1 to persistent on-disk Codex agent definitions in this environment.

   Convert each Claude agent into one of these:
   - a dedicated Codex skill when the behavior should be reusable
   - a reference file with a prompt template when the behavior is specialized but not broad enough for a skill
   - explicit `spawn_agent` guidance inside a skill when the user may ask for delegated execution

   When translating agent prompts, keep only the role, scope, and output contract. Drop Claude-specific permission or tool metadata that has no Codex equivalent.

7. Convert `.claude/commands/**`

   Claude slash commands usually become one of these in Codex:
   - a skill with a strong `description`
   - a `default_prompt` in `agents/openai.yaml`
   - a short section in a broader skill when the command is only one entry point into the same workflow

   Do not create a separate Codex skill for every tiny slash command if several commands are just aliases for one workflow.

8. Review `.claude/settings*.json` and hooks

   Settings, permission allowlists, and hooks are not skill content by default.

   Migrate them selectively:
   - permission preferences -> document assumptions or required approvals in the skill body
   - hooks -> move the intent into repo automation or a manual follow-up note
   - plugin or MCP configuration -> document as environment prerequisites, not as frontmatter fields

9. Add or refresh `agents/openai.yaml`

   Create:
   - `interface.display_name`
   - `interface.short_description`
   - `interface.default_prompt`

   Only add icons, brand color, or dependency metadata when the environment actually needs them.

10. Validate the skill

   If the `skill-creator` system skill is available, run its validator:

   ```bash
   python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py <path-to-skill>
   ```

   If that path does not exist, validate manually:
   - `SKILL.md` has only `name` and `description` in frontmatter
   - the description clearly states when to trigger the skill
   - `agents/openai.yaml` quotes all string values

## Guardrails

- Prefer repo-local `.codex/skills/` when the migration is specific to this repository.
- Keep `SKILL.md` lean; move long schemas, mapping notes, or examples into `references/`.
- Preserve source intent, but rewrite for Codex's actual behavior instead of emulating Claude syntax.
- Do not promise automatic subagent use. In this environment, delegation is conditional and must respect Codex's own rules.
- Call out residual manual work when hooks, settings, or local-only permissions have no clean Codex equivalent.

## Output

When the migration is complete, summarize:
- which Claude artifacts were consumed
- which Codex skills or references were created or updated
- which Claude features had no direct Codex equivalent
- which manual follow-ups remain
