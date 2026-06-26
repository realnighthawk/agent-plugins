# Memory Skill Layer — Design Spec

**Date:** 2026-06-24  
**Status:** Implemented (skills authored; hook formatter gap open)  
**Scope:** Agent-side behavioral contract for memory read/write/injection across Claude Code, Cursor, OpenClaw  
**Related:** [Skill-layer memory (2026-06-05)](./2026-06-05-skill-layer-memory-design.md), [LLM-native per-turn protocol (2026-06-07)](./2026-06-07-llm-native-per-turn-memory-design.md), [Episodic event model (agent-brain)](../../../agent-brain/docs/superpowers/specs/2026-06-23-episodic-event-model-design.md)

---

## 1. Summary

Memory behavior is split across two planes:

| Plane | Responsibility | Where |
|-------|----------------|-------|
| **Behavioral layer** | When to read/write, safety, subtlety, consistency | Seven plugin skills (`memory-*`) |
| **Storage layer** | Events, graph triples, episodic processing, EMU recall | `agent-brain` backend + plugin hooks |

The model is a **consumer** of pre-processed memory (`memory_search` → EMU assemblies). It does not simulate EMU formation, clustering, or storage internals.

---

## 2. System goals

### Primary

- Enable long-term personalization
- Maintain consistency across sessions
- Reduce user friction

### Safety

- Prevent storage of sensitive data
- Enforce strict boundaries
- Maintain user control

### Quality

- Keep memory relevant, minimal, and accurate
- Avoid overfitting or hallucination
- Ensure natural, invisible personalization

---

## 3. High-level flow

```
User Input
    ↓
[Memory Read Layer]        memory_search (skill + hooks)
    ↓
[Context Injection Layer]  session-start + per-turn additionalContext
    ↓
[Core Reasoning / LLM]
    ↓
[Personalization Layer]    memory-personalization skill
    ↓
[Response Generation]
    ↓
[Memory Write Evaluation]  memory-write skill (crystallization gate)
    ↓
[Memory Store]             memory_write → events → episodes → EMUs (async)
```

Hooks automate read/inject on session start and every user prompt. Writes are **LLM-driven** after each response (no Stop-hook heuristic).

---

## 4. Skill mapping

| Skill | MCP tools | Responsibility |
|-------|-----------|----------------|
| `memory-read` | `memory_search` | When to recall; treat EMUs as probabilistic bias |
| `memory-write` | `memory_write`, `search_event_context`, `set_intention`, `ingest_skill` | Crystallization gate; episodic event payload |
| `memory-policy` | (behavioral) | Content safety — what may be stored |
| `memory-boundary` | (behavioral) | Model must not simulate memory internals |
| `memory-context-injection` | (behavioral) | Relevance-first, minimal, soft influence |
| `memory-personalization` | (behavioral) | Subtle application of preferences/constraints |
| `memory-consistency` | (behavioral) | User overrides; explicit > inferred; recent > old |

Skill sources: `plugins/claude-code/skills/memory-*/SKILL.md`.  
`memory-write` body is assembled from `plugins/shared/memory-write-{decisions,payload}.md` via `scripts/sync-agent-brain-skills.sh`.

**Removed:** monolithic `skills/agent-brain/SKILL.md`, Stop-hook `index-heuristic.sh`, regex capture tiers, single-fact `memory_write` fields (`subject`, `content`, `signal_type`).

---

## 5. Storage model (backend — not agent-facing)

Agents do **not** read or write a `{ preferences[], behaviors[], constraints[] }` JSON document. That shape is pedagogical. Production storage:

| Layer | Structure | Access |
|-------|-----------|--------|
| Write | Episodic events + SPO `facts[]` | `memory_write` |
| Graph | `subjects` + `subject_edges` | `query_knowledge_graph`, `search_event_context` |
| Recall | `MemoryAssembly` with ranked EMUs | `memory_search` → `RecallEMU` |
| User rollup | Domain-grouped preference snapshot | `memory_preference_profile` |
| Legacy | `memories` table (content + `signal_type`) | Workers, inference, preference profiles — not the MCP write path |

Preferences, behaviors, and constraints emerge as graph facts (`predicate: "prefers"`, `"avoids"`, etc.) and as high-activation EMUs after the async pipeline (events → episode workers → EMU worker).

---

## 6. Read path (`memory-read`)

**Tool:** `memory_search({ query, limit? })` → `MemoryAssembly`:

```json
{
  "query_hash": "...",
  "emus": [{ "id": "...", "activation_score": 0.82, "salience": 0.7, ... }],
  "context_tags": ["morning", "fitness"],
  "duration_ms": 42
}
```

**When to call:** personalization, planning, long-term context, constraint enforcement.  
**When not to call:** general knowledge, self-contained tasks, pre-write vocabulary lookup (use `search_event_context`).

**Scoring (server):** semantic, temporal, recency, frequency, stability, reinforcement — with diversity penalty and conflict resolution in assembly. Agent uses `activation_score`, `salience`, `reinforcement_score` as confidence hints only.

**Automation:** `session-start.sh` and `recall.sh` call `memory_search` without model initiation.

---

## 7. Write path (`memory-write`)

**Gate — crystallization:** After each response, ask: *Did this exchange produce something net-new that should survive beyond this session?* If no → skip.

**Classify before writing:**

| Content | Tool |
|---------|------|
| Task / TODO / follow-up | `set_intention` |
| Fact / preference / decision / event | `memory_write` (episodic) |
| Reusable agent rule for repo | `ingest_skill` |

**Protocol:**

1. `search_event_context({ query, kinds: "entities,predicates" })`
2. `memory_write` with `event_id`, `trigger`, `type`, `timestamp`, `confidence`, optional `participants`, `entities`, `facts[]`

Confidence floor: **0.65** — skip rather than guess.  
Policy blocks (health, politics, identity, secrets): **`memory-policy` skill** — not server-side content filtering on event writes.

**Removed:** `memory_write_batch`, single-fact `memory_write` (`subject` + `content` + `signal_type`), `memory_write_event` (renamed to `memory_write`).

---

## 8. Policy vs IAM

Two distinct “policy” concepts:

| | `memory-policy` skill | `AgentPolicy` (server IAM) |
|--|----------------------|---------------------------|
| Scope | Content safety categories | Which agent may write, signal tiers, domain ACLs |
| Enforced by | Model behavior | `write.Writer` on legacy path; IAM on all paths |
| Sensitive data blocks | Yes (instructional) | No content-category filter on events |

When uncertain about safety → do not write (skill). Server defaults: if uncertain at IAM → reject agent.

---

## 9. Context injection (hooks + `memory-context-injection`)

### Session start (three tiers + intentions)

| Tier | API | Injected header |
|------|-----|-----------------|
| Agent | `retrieve_skills_for_context` | `## Agent context` |
| User | `memory_preference_profile` | `## Your profile` |
| Project | `memory_search(cwd_basename)` | `## Project context` |
| — | `check_intentions` | `## Pending intentions` |
| — | `list_entity_types` | `## Entity taxonomy` |

Cap: ~4800 chars total; project tier truncated first.

### Per turn

`memory_search` (with `exclude_subjects` from session) + `check_intentions` → merged `additionalContext`.

### Known gap

`format-recall.sh` still formats the **legacy** `{ memories: [{ content, subject_raw }] }` shape. `memory_search` now returns `{ emus: [...] }`. Hook injection may be empty until formatters are updated. Skills still govern model-initiated `memory_search` usage.

---

## 10. Personalization and consistency

**Personalization** (`memory-personalization`): adjust content, format, tone, decisions — subtly, only when relevant, with optionality preserved.

**Consistency** (`memory-consistency`):

1. User explicit input **always** overrides memory
2. Recent > old; explicit > inferred
3. Apply only when context-relevant
4. Weight by activation/salience/reinforcement scores

**Boundary** (`memory-boundary`): never describe vector DBs, EMU construction, or clustering; never invent preferences absent from recall output.

---

## 11. Decision logic

### Write

```
IF (explicit OR repeated/crystallized)
AND (policy-safe per memory-policy)
AND (confidence ≥ 0.65)
→ memory_write or set_intention
ELSE → skip
```

### Read

```
IF (relevant to query)
AND (activation_score warrants bias)
→ include in reasoning
ELSE → ignore
```

### Apply

```
IF (user overrides in current turn)
→ ignore memory for that dimension
ELSE
→ apply with strength ∝ activation_score / salience
```

---

## 12. Failure modes

| Problem | Mitigation |
|---------|------------|
| Over-personalization | Keep optionality; memory-personalization rules |
| Memory drift | Recency weighting in EMU scoring; user override |
| Hallucinated memory | memory-boundary; read only from tool output |
| Sensitive leakage | memory-policy; when uncertain, don't store |
| Write/recall lag | Fresh events not in EMUs until async workers run |
| No outcome feedback | `FeedbackEMU` exists server-side; plugins do not call it yet |

---

## 13. Deployment

Memory protocol skills are intended to be **server-side** (retrieved via `retrieve_skills_for_context` after `ingest_skill`). Install comments note this; `sync-agent-brain-skills.sh` currently assembles only `memory-write/SKILL.md` from shared fragments. Full seven-skill server ingest is manual / follow-up.

Local copies in `plugins/claude-code/skills/memory-*/` are the source of truth for skill content.

---

## 14. Removed (do not reintroduce)

- `skills/agent-brain/SKILL.md` (split into seven skills)
- `lib/index-heuristic.sh` / `indexCandidates()` regex capture
- Stop-hook `memory_write` routing
- Single-fact `memory_write` API (`subject`, `content`, `signal_type`, `memory_type`)
- `memory_write_batch`
- `memory_write_event` (absorbed into `memory_write`)
- Hybrid memory recall as `memory_search` implementation (replaced by `RecallEMU`)
