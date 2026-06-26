# LLM-Native Per-Turn Memory Protocol

**Date:** 2026-06-07  
**Last updated:** 2026-06-24  
**Status:** Implemented (superseded in detail by [memory skill layer spec](./2026-06-24-memory-skill-layer-design.md))  
**Replaces:** Stop hook index heuristic (regex tier matching in `lib/index-heuristic.sh` / `indexCandidates()`)

---

## 1. Problem

The Stop hook `index-heuristic.sh` (and its TypeScript equivalent `indexCandidates()`) detected memory-worthy signals using regex tier matching. That produced:

1. **Poor subject quality** — slugified raw message labels polluting the subject registry.
2. **Structural under-capture** — no multi-turn conversational context at session end.

The per-turn protocol with full context is now the **complete and authoritative** write path. Stop hooks are intention-completion only.

---

## 2. Goals

| ID | Goal |
|----|------|
| G1 | All memory writes use full conversational context — no regex |
| G2 | Crystallization gate + task/fact classification before write |
| G3 | Stop hook completion-only — no new writes at session end |
| G4 | Identical protocol across Claude Code, Cursor, and OpenClaw |
| G5 | Noise tolerance via confidence discipline (floor 0.65) |

---

## 3. Write targets

| Content type | Tool | Example |
|--------------|------|---------|
| Preference, correction, constraint, decision, fact | `memory_write` (episodic event) | `facts: [{ subject, predicate, object, confidence }]` |
| Task / follow-up / deferral | `set_intention` | "remind me to fix X" |
| Reusable agent rule | `ingest_skill` | project convention markdown |

**Removed:** single-fact `memory_write` with `subject` + `content` + `signal_type`.  
**Removed:** `memory_write_batch`.

---

## 4. Protocol (crystallization)

### 4.1 Trigger

After every agent response: *Did this exchange produce something net-new that should survive beyond this session?*

### 4.2 Classify

| Looks like | Route to |
|------------|----------|
| Something that needs to happen (bug, fix, TODO) | `set_intention` |
| Something that IS or WAS (preference, decision, fact) | `memory_write` |

Decompose compound content — one write per atomic fact or intention.

### 4.3 Write steps (`memory_write`)

1. `search_event_context({ query, kinds: "entities,predicates" })`
2. Construct episodic payload: `event_id`, `trigger`, `type`, `timestamp`, `confidence`, `entities[]`, `facts[]`
3. Call `memory_write`

See `plugins/shared/memory-write-payload.md` and `memory-write/SKILL.md`.

### 4.4 Confidence

| Evidence | Confidence |
|----------|-----------|
| User stated explicitly | 0.90–0.95 |
| User confirmed when asked | 0.80–0.85 |
| Synthesized across turns | 0.70–0.80 |
| Inferred from implicit context | 0.65–0.75 |
| Uncertain | **Skip** (do not write) |

### 4.5 Policy

Sensitive categories (health, politics, identity, secrets): follow **`memory-policy` skill**. Server IAM (`AgentPolicy`) governs agent write permissions separately — not content safety on events.

---

## 5. Session lifecycle

```
Session Start
  → retrieve_skills_for_context + memory_preference_profile
  → memory_search (project tier) + check_intentions + list_entity_types
  → inject merged context block

Per-turn (user message)
  → recall hook: memory_search + check_intentions
  → save triggered intention IDs

Per-turn (after agent response)  ← PRIMARY WRITE PATH
  → memory-write skill: crystallization → classify → memory_write / set_intention

Stop / agent_end
  → complete_intention for triggered IDs → delete state file
  → (no heuristic, no new writes)
```

---

## 6. Component changes (completed)

### Deleted

- `plugins/claude-code/scripts/lib/index-heuristic.sh`
- `plugins/cursor/hooks/lib/index-heuristic.sh`
- `indexCandidates()` and regex constants in OpenClaw `format.ts`
- `skills/agent-brain/SKILL.md`

### Simplified hooks

- `index.sh` (Claude Code / Cursor): triggered intentions only
- `capture.ts` (OpenClaw): intention completion only

### Skill content

Protocol lives in seven `memory-*` skills, not `agent-brain-claude-code.md`. Agent-tier plugin skills may still exist for tool discipline but memory protocol is in `memory-write`, `memory-read`, etc.

---

## 7. Noise tolerance

1. **Idempotency** — same `event_id` is a no-op
2. **Graph enrichment** — repeated facts strengthen edges
3. **EMU scoring** — low-confidence events surface weakly after async pipeline
4. **Confidence floor** — 0.65 minimum per skill

**Removed:** dedup via `write.Writer` content hash on single-fact path (legacy).

---

## 8. Testing

| Scenario | Expected |
|----------|----------|
| User states preference | Episodic `memory_write` with `prefers` fact |
| Task discovered by agent | `set_intention`, not memory |
| Nothing durable | No write |
| Stop hook fires | Only `complete_intention`; no `memory_write` |

---

## 9. Out of scope

- Session-start recall flow (unchanged)
- Intention lifecycle (unchanged)
- `FeedbackEMU` outcome loop from plugins
- Recall hook formatter for EMU shape
