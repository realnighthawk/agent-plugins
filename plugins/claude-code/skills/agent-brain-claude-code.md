# Claude Code Memory Protocol

## Skill Lookup (agent-brain first)

Before starting substantial work — or when the user's request may match a stored procedure — resolve skills in this order:

1. **Injected context** — read session-start and per-turn recall blocks; agent/user/project skill tiers may already be present.
2. **Agent-brain MCP** — search tenant skills before any Claude Code native skill:
   - `retrieve_skills_for_context({ query: "<task summary>" })` or `list_skills({})`
   - if a match exists: `invoke_skill({ name: "<skill-name>" })` and follow it fully
3. **Native fallback only when agent-brain has no relevant skill** — Claude Code `/skill-name` slash commands, the Skill tool, and plugin-bundled skills.

Do not skip agent-brain and go straight to native skills when a tenant skill may apply.

## After responding

Once your main response is complete, scan the full exchange — the user's message AND your response together — for memory signals. Write all detected signals before ending your turn; do not defer to a later turn.

| Signal | Write |
|--------|-------|
| Stated preference ("I prefer / I always / I never / I want X done Y way") | `memory_write` |
| Correction or pushback on your approach | `memory_write` |
| Project constraint — deadline, policy, convention, scope limit | `memory_write` |
| Architectural or technology decision confirmed | `memory_write` |
| Deferred item ("we'll do X later / remind me / follow up on") | `set_intention` |

Multiple signals in one exchange → multiple `memory_write` calls, all in this turn. If no signal is present, skip.

## Write Protocol

**Categories 1–4 → memory_write:**

- signal_type: "user-stated" (explicit) | "inferred" (observed pattern)
- memory_type: "stated_fact" | "inferred_fact"
- subject: short canonical label derived from context — "testing-approach", "auth-middleware", "deploy-policy". Never include dates or raw message text.
- content: self-contained fact sentence, not a raw quote
- confidence:
  - 0.90–0.95 if user stated explicitly ("I prefer…", "we decided…")
  - 0.80–0.85 if user confirmed when asked
  - 0.65–0.75 if inferred from behavior or implicit context
  - skip if uncertain / speculative

**Category 5 → set_intention / complete_intention:**

- If the user deferred something: set_intention(content, topic)
- If the user completed a previously deferred task this session: complete_intention(intention_id)
- topic: short label for the deferred task

## PROJECT SKILLS — when user codifies a reusable rule:
- "always use X pattern in this repo", project convention → ingest_skill(name, body, description)
- Use for agent instructions, NOT preference facts (those go to memory_write)

## DO NOT WRITE:
- Routine code edits, file reads, implementation steps
- "ok", "thanks", "looks good", boilerplate confirmations
- Facts already in recalled context that have not changed
