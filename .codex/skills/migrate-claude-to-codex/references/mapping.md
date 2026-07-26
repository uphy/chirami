# Claude to Codex Mapping

## Source Basis

Use these sources as the compatibility baseline:

- Anthropic Claude Code memory docs for `CLAUDE.md`
- Anthropic Claude Code settings docs for `.claude/settings*.json`
- Anthropic Claude Code hooks docs for hook semantics
- Anthropic Claude Code subagent docs for `.claude/agents/**`
- Anthropic Claude Code slash command docs for `.claude/commands/**`
- Local Codex `skill-creator` guidance for `SKILL.md` and `agents/openai.yaml`

In this repository, the practical source of truth is often the pairwise diff between:
- `.claude/skills/<name>/SKILL.md`
- `.codex/skills/<name>/SKILL.md`

Use that diff to infer the team's preferred Codex phrasing before creating new skills.

## Artifact Mapping

| Claude artifact | Preferred Codex target | Notes |
| --- | --- | --- |
| `CLAUDE.md` | Codex skill body or `references/` | Keep durable project context; do not paste the whole file |
| `.claude/rules/*.md` | Focused Codex skill or reference file | Preserve path scoping explicitly |
| `.claude/skills/*` | `.codex/skills/*` | Usually a structured rewrite with simpler frontmatter |
| `.claude/agents/*` | Codex skill, prompt template, or `spawn_agent` guidance | No direct persistent agent-file equivalent here |
| `.claude/commands/*` | Skill trigger plus `agents/openai.yaml` `default_prompt` | Treat commands as entry points, not a separate product surface |
| `.claude/settings*.json` | Manual notes, repo automation, or environment prerequisites | Not usually stored inside the skill itself |
| Claude hooks | Manual follow-up or external automation | Preserve intent, not raw JSON |

## Mechanical Rewrite Rules

Apply these rewrites when copying a Claude skill into Codex:

1. Reduce frontmatter to:

   ```yaml
   ---
   name: my-skill
   description: What it does and when to use it.
   ---
   ```

2. Remove Claude-only frontmatter such as:
   - `license`
   - `compatibility`
   - `metadata`

3. Replace tool names and workflow instructions:
   - `AskUserQuestion` -> ask the user directly, briefly, and only when needed
   - `TodoWrite` -> `update_plan` when there is meaningful multi-step coordination
   - `Task` / subagent references -> `spawn_agent` guidance only if the user explicitly wants delegation

4. Replace Claude slash command phrasing:
   - `/command-name` -> explicit skill mention like `$skill-name`
   - command placeholders -> ordinary prompt examples in `default_prompt` or `SKILL.md`

5. Rewrite product assumptions:
   - Claude permission allowlists do not become skill metadata
   - Claude hooks do not become frontmatter
   - Claude agent files do not become `agents/openai.yaml`

## Non-1:1 Areas

### Claude subagents

Claude project subagents are file-defined specialists. In this Codex environment, reusable specialization lives primarily in skills, while execution-time delegation is handled by `spawn_agent`.

Use this decision rule:
- Reusable specialist behavior -> create a Codex skill
- One-off delegated execution pattern -> document how to `spawn_agent`
- Narrow internal helper prompt -> keep it in `references/` unless it deserves full skill status

### Claude settings and hooks

Claude settings files often contain:
- permission allowlists
- hook commands
- plugin enablement

These are usually environment concerns, not skill content. Preserve them by:
- documenting prerequisites in the skill
- creating follow-up repo automation tasks
- explicitly listing what cannot be auto-migrated

## Practical Migration Heuristics

- If the source content teaches Codex how to reason about a code area, keep it in `SKILL.md`.
- If the source content is detailed reference material, move it to `references/`.
- If the source content only changes entry points, prefer `agents/openai.yaml` plus a stronger skill description.
- If the source content mainly automates local shell behavior, keep it out of the skill and note it as follow-up work.

## Migration Checklist

- Inventory every Claude artifact present in the repo
- Decide which items become skills, references, docs, or manual follow-ups
- Rewrite skill frontmatter to Codex format
- Add `agents/openai.yaml` for each new Codex skill
- Validate each new or updated skill
- Report non-portable Claude features explicitly
