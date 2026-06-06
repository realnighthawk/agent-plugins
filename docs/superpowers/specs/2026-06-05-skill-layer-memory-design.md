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
    └─ complete_intention for each triggered ID in state file → delete file
```

Cross-agent consistency falls out naturally: user and project tiers are read from the server, shared across all agents on the same API key.

---

## Components

### Claude Code (`plugins/claude-code`)

- **`scripts/session-start.sh`** — four parallel fetches (three skill tiers + `check_intentions`); emits merged block + `## Pending intentions` section as `additionalContext`; appends triggered intention IDs to `/tmp/agent-brain-triggered-intentions-<sid>`
- **`scripts/recall.sh`** — two parallel fetches (`memory_search` with `exclude_subjects` + `check_intentions`); merges both blocks into `additionalContext`; appends triggered IDs to state file
- **`scripts/index.sh`** — Completion-only: reads triggered-intentions file → complete_intention per ID → deletes file. No new writes.
- **`scripts/lib/session-skill.sh`** *(new)* — shared merge logic: truncate each tier, concatenate with section headers, enforce token cap
- **`scripts/lib/format-recall.sh`** — added `agent_brain_format_intentions` alongside existing `agent_brain_format_recall`
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

**Complete triggered intentions:**
- Read `/tmp/agent-brain-triggered-intentions-<sid>`
- Call `complete_intention(intention_id)` for each ID (intentions acted on during session)
- Delete state file

### Intentions state file lifecycle

| Event | File operation |
|-------|---------------|
| SessionStart: `check_intentions` returns triggered IDs | `>> /tmp/agent-brain-triggered-intentions-<sid>` |
| UserPromptSubmit: `check_intentions` returns triggered IDs | `>> /tmp/agent-brain-triggered-intentions-<sid>` |
| Stop: complete_intention phase | Read file, call API per line, `rm -f` |
| Session never reaches Stop (crash, kill) | File left in `/tmp`; harmless; cleaned by OS |

### After-each-response protocol (agent tier — two-phase)

The agent-tier skill gives Claude an explicit two-phase protocol to run after every response. This is the primary capture path for mid-session facts; the Stop hook handles intention completion only.

**Phase 1 — Reflect:** Ask what emerged in this conversation turn that future-you wouldn't know from reading the code or git history. Use the full conversation context. List candidates before writing any.

**Phase 2 — Category Audit (backstop):** For each category below, if Phase 1 did not already produce a candidate, check explicitly:
1. **Preference** — did the user state or confirm how they like things done?
2. **Correction** — did the user push back, say you were wrong, or redirect?
3. **Project constraint** — did a deadline, policy, convention, or scope limit emerge?
4. **Architectural decision** — was a design choice, technology, or pattern decided or confirmed?
5. **Deferred intention** — was something identified as "do later", "follow up", or "remind me"?

**Write protocol — Categories 1–4 → `memory_write`:**
- `signal_type`: "user-stated" (explicit) | "inferred" (observed pattern)
- `memory_type`: "stated_fact" | "inferred_fact"
- `subject`: short canonical label derived from context; never include dates or raw message text
- `content`: self-contained fact sentence, not a raw quote
- `confidence`: 0.90–0.95 explicit, 0.80–0.85 confirmed, 0.65–0.75 inferred; skip if speculative

**Category 5 → `set_intention`:** content + topic (short label for the deferred task)

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
