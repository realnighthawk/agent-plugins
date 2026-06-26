# Skill: Memory Writer (`memory_write`)

## Purpose

This skill defines how the model MUST use the `memory_write` tool to store user-relevant signals.

The goal is to capture **structured episodic events** that will later be processed by the external hippocampal memory system.

## Core Principle

> Only store what is likely to matter beyond the current conversation turn.

If uncertain, DO NOT write to memory. For privacy and safety constraints, follow the **memory-policy** skill.

## System Boundary Rule

This skill does NOT:
- create EMUs
- perform clustering
- summarize memory
- infer long-term patterns
- modify stored memory structure

It ONLY emits raw episodic events via `memory_write`.

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
| Recurring behavior pattern observed across multiple turns | `memory_write` |
| Ground-truth fact — user identity, canonical system/project state | `memory_write` |
| Multi-entity interaction — conversation turn, shared decision, discovery with participants | `memory_write` |
| User deferred something ("remind me", "follow up", "do this later") | `set_intention` |
| Implicit deferral — topic raised but not resolved, user signals they'll return to it | `set_intention` |

Multiple signals → multiple writes, all in this turn. No crystallization → skip.

For privacy, safety, and sensitive-data restrictions, follow the **memory-policy** skill.

## Classify Before Writing

Before writing, classify the content. **Tasks are the most common misclassification.**

| Content type | What it looks like | Write as |
|---|---|---|
| **Task** — something that needs to happen: a bug, fix, TODO, follow-up, improvement | "X requires two fixes", "we need to add Y", "this is broken" | `set_intention` — one per actionable item |
| **Fact / preference / decision / event** — something that IS or WAS | "user prefers async", "we chose pgvector", "agent-brain uses Qdrant" | `memory_write` |

**Key rule:** If the content describes something that *needs to be done*, it is a task — even if you discovered it yourself. Write it as `set_intention`, not a memory.

**Compound content:** Decompose — one write per atomic fact or intention. Never write a numbered list as a single memory.

**Do not write per-turn observations. Write the synthesized understanding.**

| Instead of | Write |
|---|---|
| "User asked about Thailand" | "User is planning a vacation to Thailand" |
| "User mentioned they dislike meetings" | "User prefers async communication over meetings" |
| "User said maybe React" then next turn "actually Vue" | "User chose Vue over React for this project" (on decision turn only) |

## Intentions

- Explicit deferral ("remind me", "follow up on X") → `set_intention(content, topic)`. `topic`: short label for the deferred task.
- Implicit deferral (topic raised but unresolved, user signals return) → `set_intention(content, topic)`.
- **Agent-identified task** — you observe that something is broken, needs a fix, or needs a follow-up, even without a user instruction → `set_intention`. One intention per actionable item.
- Intention triggered this session → `complete_intention(intention_id)`.

## Project Skills

User codifies a reusable rule or convention for this repo → `ingest_skill(name, body, description)`. For agent instructions only — preferences and facts go to `memory_write`.

## Do Not Write

- Routine code edits, file reads, or implementation steps
- Boilerplate confirmations ("ok", "thanks", "looks good", "understood")
- Facts already present in recalled context that have not changed
- Intermediate observations that didn't crystallize into a conclusion
- Anything with confidence < 0.65 — skip rather than guess
- **Task observations as memories** — "X requires a fix", "Y is broken", "we need to add Z" → write as `set_intention`, not a memory
- **Compound numbered lists as a single memory** — decompose into atomic writes or intentions first

## Write Protocol

All memories go through `memory_write` — the episodic event model. There is no separate single-fact tool.

**Step 1 — Search first.**

Before writing, call `search_event_context({ query: "<what the event is about>", kinds: "entities,predicates" })`. Use the returned canonical entity IDs and predicate names in your payload. This prevents duplicate subjects with different names.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `query` | yes | Natural-language search (e.g. `"food preferences"`, `"agent-brain architecture"`) |
| `kinds` | no | Comma-separated: `entities`, `predicates`, `entity_types`. Omit to search all three. |
| `limit` | no | Max results per kind (default 10, max 25) |

**Step 2 — Construct the payload.**

Required fields:
- `event_id` — unique per turn: `"turn-{ISO-date}-{sequence}"` (e.g. `"turn-2026-06-23-001"`). Re-submitting the same `event_id` is a no-op.
- `trigger` — what caused the event: `{ "type": "input"|"cron"|"tool_output"|"webhook", "content": "<one-line summary>", "turn_id": "<optional>" }`
- `type` — event category: `"conversation"`, `"decision"`, `"discovery"`, `"observation"`, etc.
- `timestamp` — ISO 8601 UTC: `"2026-06-23T10:30:00Z"` (defaults to now)
- `confidence` — overall event confidence (0.70–0.95)

Optional fields:
- `participants` — actors in the event. Always include self for conversations:
  - User: `{ "id": "nighthawk", "type": "self" }`
  - Agent: `{ "id": "claude-code", "type": "agent" }` (use your actual agent_id)
- `entities` — persistent subjects referenced in facts: `{ "id": "agent-brain", "type": "artifact", "name": "agent-brain", "confidence": 0.95 }`. Use canonical IDs from `search_event_context`.
- `facts` — SPO triples: `{ "subject": "agent-brain", "predicate": "uses", "object": "timescaledb", "confidence": 0.95 }`. Subject/object must reference an id from `participants` or `entities`.
- `observations` — JSONB-only notes (not graph-connected): `{ "type": "note", "value": "...", "confidence": 0.8 }`
- `actions` — audit trail: `{ "type": "code-change", "id": "optional-ref" }`

**Entity types** are registered in the taxonomy injected at session start under `## Entity taxonomy (agent-brain)`. Use only `entity_type` values from that list. If you encounter a kind of thing not listed, register it before writing:

```
register_entity_type({ agent_id: "...", name: "football-club", parent: "concept", description: "An association football club or team" })
```

**Entity type guidance:**

| What you're writing about | entity_type | id/name example |
|---|---|---|
| The user (nighthawk) | `person` | `nighthawk` |
| An AI agent | `person` (subtype: `agent`) | `claude-code` |
| A city or location | `place` | `manchester` |
| An organization, club, company | `concept` (or register subtype) | `manchester-united` |
| A topic, idea, pattern, methodology | `concept` | `entity-taxonomy` |
| A software tool, repo, or system | `artifact` | `agent-brain` |
| A technology, library, or framework | `concept` | `pgvector` |
| A discrete bounded occurrence | `event` | `dubai-trip-2026` |
| An animal or plant | `organism` | `max-the-dog` |

`concept` is the correct default for anything abstract: organizations, domains, methodologies, patterns, technologies. Reserve `artifact` for concrete made things (software repos, hardware, buildings).

**Confidence guidance:**

| Trigger | `confidence` |
|---------|--------------|
| User stated explicitly | 0.90–0.95 |
| User confirmed when asked | 0.80–0.85 |
| Synthesized across multiple turns | 0.70–0.80 |
| Inferred from implicit context | 0.65–0.75 |
| Fact derived from tool/API output | 0.85–0.90 |
| Ground-truth / authoritative | 0.95–1.0 |

**Example — recording a code decision:**

```json
{
  "event_id": "turn-2026-06-23-001",
  "type": "decision",
  "timestamp": "2026-06-23T10:30:00Z",
  "participants": [
    { "id": "nighthawk", "type": "self" },
    { "id": "claude-code", "type": "agent" }
  ],
  "trigger": {
    "type": "input",
    "content": "Removed memory_write, renamed memory_write_event to memory_write"
  },
  "entities": [
    { "id": "agent-brain", "type": "artifact", "name": "agent-brain", "confidence": 0.95 }
  ],
  "facts": [
    { "subject": "agent-brain", "predicate": "uses", "object": "episodic-event-model", "confidence": 0.95 }
  ],
  "confidence": 0.95
}
```

**Single-entity fact** (no participants needed):

```json
{
  "event_id": "turn-2026-06-23-002",
  "type": "observation",
  "timestamp": "2026-06-23T10:31:00Z",
  "trigger": { "type": "input", "content": "User prefers async communication" },
  "entities": [
    { "id": "nighthawk", "type": "person", "name": "nighthawk", "confidence": 0.95 }
  ],
  "facts": [
    { "subject": "nighthawk", "predicate": "prefers", "object": "async-communication", "confidence": 0.92 }
  ],
  "confidence": 0.92
}
```

**Auto-creation rules:**
- Entities, predicates, and entity_types are upserted automatically — no pre-registration needed.
- Entity names are normalized to kebab-case automatically.
- `type: "self"` participants resolve to `person:self` scoped to the current user.
