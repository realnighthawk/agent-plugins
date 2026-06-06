# Skill-Layer Memory Backend — Design Spec

**Date:** 2026-06-05
**Status:** Implemented
**Scope:** Claude Code, Cursor, OpenClaw plugins + agent-brain server-side skills

---

## Problem

The three agent-brain plugins (Claude Code, Cursor, OpenClaw) share a common set of gaps:

- **Capture is too narrow.** Only explicit preference keywords ("I prefer", "I like") trigger `memory_write`. Architectural decisions, debugging patterns, and workflow habits are missed.
- **Recall is passive.** Memories are injected as a flat bullet list before each prompt but the AI has no model of who the user is at session start — it learns nothing from prior sessions before the first word is typed.
- **Cross-agent inconsistency.** Claude Code and Cursor maintain separate runtime state; a preference expressed in one is not automatically available to the other.
- **No personalization.** Communication style, expertise level, and project conventions are not part of the AI's operating context.

The `memory_preference_profile` call in `session-start.sh` already fetches a user profile on every session — but the result is discarded (`>/dev/null`). The user tier is effectively free to add.

---

## Approach: Three-Tier Skill Layers

Server-side skill content is fetched once at session start, merged into a single context block, and injected before the first prompt. Per-turn recall is made more targeted by excluding subjects already covered by session-start.

### Tier model

| Tier | API call | Content | Update cadence |
|------|----------|---------|----------------|
| **Agent** | `retrieve_skills_for_context("agent:<agent_id>")` | Tool discipline, memory rules, plugin-specific behavior | Rarely — authored once per plugin, updated with plugin releases |
| **User** | `memory_preference_profile({})` | Communication style, expertise level, cross-session workflow preferences | Grows automatically as memories accumulate |
| **Project** | `memory_search({query: <cwd_basename>, limit: 6})` | Repo conventions, architectural decisions, active work context | Updates each session as project memories are written |

---

## Architecture

```
SessionStart
    │
    ├─ retrieve_skills_for_context("agent:<agent_id>")   → Agent tier
    ├─ memory_preference_profile({})                      → User tier
    ├─ memory_search({query:<cwd_basename>})              → Project tier
    └─ check_intentions({context_text:"session start <cwd>"})  → Pending intentions
    │
    ▼
  merge + enforce 1200-token cap
  + append ## Pending intentions section
  + save triggered intention IDs to /tmp/agent-brain-triggered-intentions-<sid>
    │
    ▼
  inject once as session context
    │
    ▼
  Per-turn recall (UserPromptSubmit)
    ├─ memory_search (excludes session subjects) → recall block
    └─ check_intentions (context=prompt)         → intentions block
    → merged additionalContext; triggered IDs appended to state file
    │
    ▼
  Stop
    ├─ complete_intention for each triggered ID in state file → delete file
    └─ index heuristic → route candidates to memory_write / set_intention
```

Cross-agent consistency falls out naturally: user and project tiers are read from the server, shared across all agents on the same API key.

---

## Components

### Claude Code (`plugins/claude-code`)

- **`scripts/session-start.sh`** — four parallel fetches (three skill tiers + `check_intentions`); emits merged block + `## Pending intentions` section as `additionalContext`; appends triggered intention IDs to `/tmp/agent-brain-triggered-intentions-<sid>`
- **`scripts/recall.sh`** — two parallel fetches (`memory_search` with `exclude_subjects` + `check_intentions`); merges both blocks into `additionalContext`; appends triggered IDs to state file
- **`scripts/index.sh`** — three phases at Stop: (1) read state file, call `complete_intention` per ID, delete file; (2) run `agent_brain_index_candidates`; (3) route each candidate by `.action`: `set_intention` or `memory_write`
- **`scripts/lib/session-skill.sh`** *(new)* — shared merge logic: truncate each tier, concatenate with section headers, enforce token cap
- **`scripts/lib/format-recall.sh`** — added `agent_brain_format_intentions` alongside existing `agent_brain_format_recall`
- **`scripts/lib/index-heuristic.sh`** — expanded to 5 tiers; Tier 5 detects deferred phrases and returns `{action:"set_intention", content, topic}` instead of a `memory_write` candidate
- **`scripts/ingest-skills.sh`** *(new)* — standalone re-ingest script; reads all `.md` files in `skills/` and calls `ingest_skill` for each
- **`install.sh`** — calls `ingest_agent_skills()` after mcp-call installation; adds re-ingest hint to output
- **`skills/agent-brain-claude-code.md`** *(new)* — agent-tier skill body (~1400 chars); contains after-each-response write/intention protocol (see below); ingested to server at install time
- **`skills/agent-brain/SKILL.md`** — removed; agent-tier skill content is now server-side only

### Cursor (`plugins/cursor`)

- **`hooks/session-start.sh`** — same change as Claude Code
- **`hooks/recall.sh`** — same subject-exclusion change
- **`hooks/lib/session-skill.sh`** *(new)* — copy of Claude Code merge lib

### OpenClaw (`plugins/openclaw`)

- **`recall.ts`** — `before_prompt_build` fetches three tiers before injecting recall; returns `prependContext` with merged block
- **`session-state.ts`** — fix local file growth: move from `~/.openclaw/agent-brain-state/` to `/tmp` keyed on session ID (matching the fix already applied to Claude Code and Cursor)
- **`capture.ts`** — no change in this pass (Approach 3)
- **New: `session-skill.ts`** — TypeScript equivalent of merge logic

### Server-side (agent-brain)

- **Three agent-tier skills ingested via `ingest_skill`:**
  - `agent-brain-claude-code`
  - `agent-brain-cursor`
  - `agent-brain-openclaw`
  - Content: current `SKILL.md` content, migrated and extended with personalization guidance
- **User tier** — no new server work; `memory_preference_profile` already exists
- **Project tier** — no new server work; `memory_search` with project scope already works

---

## Data Flow

### Session start (once per session)

1. Set `NIGHTHAWK_SESSION_ID` from payload (no file write)
2. Fetch four calls in parallel with 8s per-fetch timeout:
   - `retrieve_skills_for_context` → Agent tier
   - `memory_preference_profile` → User tier
   - `memory_search(query=cwd_basename, limit=6, use_graph=true)` → Project tier
   - `check_intentions(context_text="session start <cwd>")` → Pending intentions
3. Merge skill tiers:
   - Truncate each tier to ~400 tokens (~1600 chars)
   - Skip empty tiers silently (no placeholders)
   - Concatenate with headers: `## Agent context`, `## Your profile`, `## Project context`
   - Hard cap: 1200 tokens (~4800 chars total); truncate project tier first if over
4. If `check_intentions` returned pending/triggered intentions, call `agent_brain_format_intentions` and append `## Pending intentions` section to block
5. Emit merged block as `additionalContext` (Claude Code/Cursor) or `prependContext` (OpenClaw)
6. Write injected subject labels to `/tmp/agent-brain-subjects-${NIGHTHAWK_SESSION_ID}` (one per line) for recall exclusion
7. If any intentions were `triggered`, append their IDs (one per line) to `/tmp/agent-brain-triggered-intentions-${NIGHTHAWK_SESSION_ID}`

### Per-turn recall (every user prompt)

1. Save prompt to state file for Stop
2. Run two calls in parallel:
   - `memory_search` with `exclude_subjects` from subjects file (omit if file absent — fallback to no exclusion)
   - `check_intentions(context_text=<prompt>)` — detects topic/time matches against pending intentions
3. Format recall block from `memory_search` result; format intentions block from `check_intentions` result
4. If `check_intentions` returned triggered intentions, append their IDs to `/tmp/agent-brain-triggered-intentions-<sid>` (append, not overwrite — accumulates across turns)
5. Merge blocks; inject as `additionalContext` — typically 2–4 recall items + any matching intentions

### Session end (Stop / agent_end)

Three phases run sequentially:

**Phase 1 — Complete triggered intentions:**
- Read `/tmp/agent-brain-triggered-intentions-<sid>`
- Call `complete_intention(intention_id)` for each ID (intentions acted on during session)
- Delete state file

**Phase 2 — Run index heuristic:**
- `lib/index-heuristic.sh` scans last user prompt for 5 tiers of signals
- Returns JSON candidate array; each item has optional `.action` field

**Phase 3 — Route candidates:**
- `.action == "set_intention"` → `set_intention(content, topic)` (Tier 5: deferred phrases; safety net for when Plane 2 agent didn't catch it mid-session)
- `.action` absent or other → `memory_write(...)` (Tiers 1–4: preferences, corrections, constraints, decisions)

Project-scoped `memory_write` subjects surface in the next session's project tier automatically.

### Intentions state file lifecycle

| Event | File operation |
|-------|---------------|
| SessionStart: `check_intentions` returns triggered IDs | `>> /tmp/agent-brain-triggered-intentions-<sid>` |
| UserPromptSubmit: `check_intentions` returns triggered IDs | `>> /tmp/agent-brain-triggered-intentions-<sid>` |
| Stop: complete_intention phase | Read file, call API per line, `rm -f` |
| Session never reaches Stop (crash, kill) | File left in `/tmp`; harmless; cleaned by OS |

### After-each-response protocol (Plane 2 — agent tier)

The agent-tier skill (`skills/agent-brain-claude-code.md`) gives Claude an explicit protocol to run after every response. This is the primary capture path for mid-session facts; the Stop hook is the safety net.

**Write triggers** (agent calls `memory_write` immediately):
- User stated a preference: "I prefer X", "I always Y", "I never Z"
- User made a correction: "no", "not that", "actually X", "wrong", "instead"
- User stated a project constraint: "in this repo", "our convention is", "we always/don't use"
- User revealed a fact: name, role, tech stack, goal, team, deadline
- Architectural decision confirmed: "let's go with X", "we decided", "use X approach"

**Write protocol:**
1. Call `memory_get(subject="<label>")` first — skip write if fact unchanged
2. Call `memory_write` with `signal_type`, `memory_type`, `subject`, `content`, `confidence`

**Intention triggers** (agent calls `set_intention` immediately):
- "remind me", "later", "I'll do X", "follow up on X" → `set_intention(content, topic)`
- Deferred task completed this session → `complete_intention(intention_id)`

**Skill triggers** (agent calls `ingest_skill`):
- User codifies a reusable project rule → `ingest_skill(name, body, description)`
- Used for agent instructions, NOT preference facts

**Do not write:** routine code edits, file reads, "ok"/"thanks"/"looks good", facts already in recalled context that have not changed.

### Subject propagation

- Memories tagged with cwd hash → project tier next session
- Memories tagged as preferences → user tier (`memory_preference_profile`) next session
- No extra API calls needed; existing `memory_write` tagging is sufficient

---

## Error Handling

**Core principle: hooks must never block the agent.**

| Failure | Behavior |
|---------|----------|
| Agent tier times out or errors | Omit tier; continue with user + project |
| User tier empty (new user) | Omit silently — no placeholder |
| Project tier empty (new project) | Omit silently — no placeholder |
| All tiers fail | Emit empty `additionalContext`; session starts clean |
| Merge exceeds token cap | Truncate project tier first, then user tier; agent tier never truncated |
| `retrieve_skills_for_context` returns unknown skill | Omit agent tier silently |
| Auth error (401/403) | Surface once per session — indicates misconfiguration |

**Timeouts:**
- Per-tier fetch: 8s
- Total session-start wall clock: 12s (parallel; incomplete tiers dropped)
- Per-turn recall: 30s (unchanged)

**OpenClaw:** Use `Promise.allSettled` — never `Promise.all`. Rejected tiers resolve to `null` and are skipped. Timeouts via `AbortController` with 8s signal.

**Not surfaced to user:** missing skills, empty tiers, network timeouts on individual fetches.
**Surfaced to user:** `memory_write` failures, auth errors.

---

## Testing

### Shell plugins (Claude Code + Cursor)

Extend `mock-mcp-call.sh` to handle `retrieve_skills_for_context` with static fixture. Add to `run-hook-tests.sh`:

| Test | Assertion |
|------|-----------|
| Session start injects all three tiers | `additionalContext` contains all three headers |
| Session start injects pending intentions | `additionalContext` contains `## Pending intentions` when fixture returns pending items |
| Session start triggered IDs written to state file | `/tmp/agent-brain-triggered-intentions-<sid>` contains IDs from fixture |
| Session start with empty user tier | Only agent + project headers present |
| All tiers fail | Hook exits 0, `additionalContext` absent or empty |
| Token cap enforced | Output ≤ 4800 chars when fixtures are oversized |
| Recall excludes session subjects | `memory_search` args contain `exclude_subjects` |
| Recall fallback when session subjects empty | `memory_search` args have no `exclude_subjects` |
| Recall calls check_intentions in parallel | Both `memory_search` and `check_intentions` MCP calls appear in mock log |
| Stop completes triggered intentions | `complete_intention` called for each ID in state file; file deleted |
| Stop routes set_intention candidates | `set_intention` called (not `memory_write`) for Tier 5 candidates |
| Stop routes memory_write candidates | `memory_write` called for Tiers 1–4 candidates |
| index-heuristic Tier 5 detection | "remind me to X" returns `{action:"set_intention", topic:"X"}` |

### OpenClaw (TypeScript)

New file `test/session-skill.test.js`:

| Test | Assertion |
|------|-----------|
| All three tiers returned | `prependContext` contains all three headers |
| One tier rejects | Remaining two tiers still injected |
| All tiers reject | `prependContext` empty, no throw |
| Merge respects token cap | Output truncated at 4800 chars, project tier trimmed first |

### Server-side skill authoring

Manual integration test: ingest three agent-tier skills, verify `retrieve_skills_for_context` returns them for the correct `agent_id`.

### Out of scope for this pass

- Cross-agent consistency (manual smoke test)
- User tier growth over time (agent-brain server tests)
- AI-driven capture quality (Approach 3)

---

## Out of Scope

- **Approach 3 (AI-driven capture):** replacing keyword heuristics with AI judgment — deferred to a follow-on spec
- **Skill authoring UX:** how users edit their user-tier skill — deferred
- **Project tier pruning/TTL:** preventing project tier bloat over time — deferred

---

## Token Budget Summary

| | Today | After this change |
|--|-------|------------------|
| Session start | ~0 useful tokens | ~1200 tokens (merged tiers) |
| Per-turn recall | ~200–600 tokens | ~100–300 tokens |
| Net over 20-turn session | ~5,000–12,000 | ~4,200–7,200 |
