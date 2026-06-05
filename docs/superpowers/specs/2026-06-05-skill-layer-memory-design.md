# Skill-Layer Memory Backend — Design Spec

**Date:** 2026-06-05
**Status:** Approved for implementation
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
    └─ memory_search({query:<cwd_basename>})              → Project tier
    │
    ▼
  merge + enforce 1200-token cap
    │
    ▼
  inject once as session context
    │
    ▼
  Per-turn recall (targeted, excludes session subjects)
    → smaller recall blocks per turn
```

Cross-agent consistency falls out naturally: user and project tiers are read from the server, shared across all agents on the same API key.

---

## Components

### Claude Code (`plugins/claude-code`)

- **`scripts/session-start.sh`** — replace discarded `memory_preference_profile` call with three parallel tier fetches; emit merged block as `additionalContext`
- **`scripts/recall.sh`** — pass `exclude_subjects` list (set during session-start) to `memory_search` to avoid re-injecting tier-covered facts
- **`scripts/lib/session-skill.sh`** *(new)* — shared merge logic: truncate each tier, concatenate with section headers, enforce token cap
- **`skills/agent-brain/SKILL.md`** — removed; agent-tier skill content migrated to server-side via `ingest_skill`

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
2. Fetch all three tiers in parallel with 8s per-tier timeout
3. Merge:
   - Truncate each tier to ~400 tokens (~1600 chars)
   - Skip empty tiers silently (no placeholders)
   - Concatenate with headers: `## Agent context`, `## Your profile`, `## Project context`
   - Hard cap: 1200 tokens (~4800 chars total); truncate project tier first if over
4. Emit merged block as `additionalContext` (Claude Code/Cursor) or `prependContext` (OpenClaw)
5. Write injected subject labels to `/tmp/agent-brain-subjects-${NIGHTHAWK_SESSION_ID}` (one per line) for recall exclusion — same `/tmp` pattern as the prompt file; shell env vars don't survive across separate hook process invocations

### Per-turn recall (every user prompt)

1. Read subject labels from `/tmp/agent-brain-subjects-${NIGHTHAWK_SESSION_ID}` if it exists
2. Run `memory_search` with `exclude_subjects: [<session subjects>]`
3. Inject result as before — typically 2–4 items instead of 6–8
4. If subjects file is absent (session-start failed or new session), fall back to current behavior with no exclusion

### Session end (Stop / agent_end)

- Index heuristic runs unchanged
- No additional changes in this pass; project-scoped `memory_write` subjects automatically surface in next session's project tier

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
| Session start with empty user tier | Only agent + project headers present |
| All tiers fail | Hook exits 0, `additionalContext` absent or empty |
| Token cap enforced | Output ≤ 4800 chars when fixtures are oversized |
| Recall excludes session subjects | `memory_search` args contain `exclude_subjects` |
| Recall fallback when session subjects empty | `memory_search` args have no `exclude_subjects` |

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
