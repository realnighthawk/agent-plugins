# Cursor Memory Protocol

## Skill Lookup

Before starting substantial work, resolve skills in this order:

1. **Injected context** — session-start and per-turn recall blocks may already contain relevant skills.
2. **Agent-brain MCP** — `retrieve_skills_for_context({ query: "<task summary>" })` or `list_skills({})`, then `invoke_skill({ name })` if matched. Follow the loaded skill fully.
3. **Native fallback** — Cursor skills (`~/.cursor/skills`, project `.cursor/skills`) and the Skill tool / `available_skills` list, only when agent-brain has no match.

Do not skip agent-brain and go straight to native skills.

## When to Write

Write only when something **crystallizes** — a new understanding, decision, preference, plan, or commitment that isn't already reflected in your recalled context. Ask after each response:

> "Did this exchange produce something net-new that should survive beyond this session?"

If yes → write. If no → skip.

**Crystallization signals:**

| Signal | Write |
|--------|-------|
| User stated a preference, constraint, or fact explicitly | `memory_write` |
| User corrected your approach or assumption | `memory_write` |
| A plan, decision, or commitment solidified across turns | `memory_write` (synthesized conclusion) |
| Architecture or technology decision confirmed | `memory_write` |
| Recurring behavior pattern observed across multiple turns | `memory_write` (`behavioral_pattern`) |
| Ground-truth fact — user identity, canonical system/project state | `memory_write` (`canonical_fact`) |
| User deferred something ("remind me", "follow up", "do this later") | `set_intention` |
| Implicit deferral — topic raised but not resolved, user signals they'll return to it | `set_intention` |

Multiple signals → multiple writes, all in this turn. No crystallization → skip.

**Do not write per-turn observations. Write the synthesized understanding.**

| Instead of | Write |
|---|---|
| "User asked about Thailand" | "User is planning a vacation to Thailand" |
| "User mentioned they dislike meetings" | "User prefers async communication over meetings" |
| "User said maybe React" then next turn "actually Vue" | "User chose Vue over React for this project" (on decision turn only) |

## Write Protocol

**Decision table** — this agent has tier 1 access; all signal types are permitted.

| Trigger | `memory_type` | `signal_type` | `confidence` |
|---------|---------------|---------------|--------------|
| User stated explicitly in conversation | `stated_fact` | `user-stated` | 0.90–0.95 |
| User confirmed when directly asked | `stated_fact` | `user-stated` | 0.80–0.85 |
| Synthesized from context across multiple turns | `inferred_fact` | `inferred` | 0.70–0.80 |
| Inferred from implicit context (single turn) | `inferred_fact` | `inferred` | 0.65–0.75 |
| Recurring behavior observed across multiple turns | `behavioral_pattern` | `behavioral` | 0.70–0.80 |
| Fact derived from a tool or API result | `inferred_fact` | `tool-output` | 0.85–0.90 |
| Ground-truth — user identity, canonical system state, immutable project fact | `canonical_fact` | `canonical` | 1.0 |

**Common fields (all writes):**
- `subject` — short canonical label, topic-derived, max ~3 words: `"testing-approach"`, `"vacation-plans"`. Never include dates or raw message text.
- `content` — one self-contained declarative sentence. Write the conclusion, not the path to it.

**`canonical_fact` constraint:** Writing one invalidates all prior memories on the same subject and cascades contradiction flags against all inferred memories on that subject. Use only when the fact is authoritative and permanent — not for preferences, decisions, or anything that could evolve.

## Intentions

- Explicit deferral ("remind me", "follow up on X") → `set_intention(content, topic)`. `topic`: short label for the deferred task.
- Implicit deferral (topic raised but unresolved, user signals return) → `set_intention(content, topic)`.
- Intention triggered this session → `complete_intention(intention_id)`.

## Project Skills

User codifies a reusable rule or convention for this repo → `ingest_skill(name, body, description)`. For agent instructions only — preferences and facts go to `memory_write`.

## DO NOT WRITE

- Routine code edits, file reads, or implementation steps
- Boilerplate confirmations ("ok", "thanks", "looks good", "understood")
- Facts already present in recalled context that have not changed
- Intermediate observations that didn't crystallize into a conclusion
- Anything with confidence < 0.65 — skip rather than guess
