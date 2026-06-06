# LLM-Native Per-Turn Memory Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Stop hook regex heuristic with a two-phase per-turn reflection protocol in all three plugin SKILL.md files, and simplify the Stop hooks to intention-completion-only.

**Architecture:** The per-turn SKILL.md protocol becomes the sole write path — Phase 1 (open reflection using full conversation context) surfaces candidates, Phase 2 (five-category audit) catches misses. Stop hooks drop the heuristic entirely and only complete triggered intentions.

**Tech Stack:** Bash (Claude Code + Cursor hooks), TypeScript (OpenClaw plugin), Markdown (SKILL.md files)

---

## File Map

| File | Change |
|------|--------|
| `plugins/claude-code/skills/agent-brain-claude-code.md` | Rewrite — new two-phase protocol |
| `plugins/claude-code/scripts/index.sh` | Remove heuristic source + candidate loop |
| `plugins/claude-code/scripts/lib/index-heuristic.sh` | **Delete** |
| `plugins/cursor/skills/agent-brain-cursor.md` | Rewrite — same protocol, Cursor platform name |
| `plugins/cursor/hooks/index.sh` | Remove heuristic source + candidate loop |
| `plugins/cursor/hooks/lib/index-heuristic.sh` | **Delete** |
| `plugins/openclaw/skills/agent-brain-openclaw.md` | Rewrite — same protocol, OpenClaw platform name |
| `plugins/openclaw/capture.ts` | Remove Phase 2 (indexCandidates loop) |
| `plugins/openclaw/format.ts` | Remove regex constants, `WriteCandidate` type, `indexCandidates()` |
| `docs/superpowers/specs/2026-06-04-claude-code-plugin-design.md` | Update index.sh row to "completion-only" |
| `docs/superpowers/specs/2026-06-05-skill-layer-memory-design.md` | Rewrite after-each-response section, remove heuristic tiers table |

---

## Task 1: Rewrite Claude Code SKILL.md

**Files:**
- Modify: `plugins/claude-code/skills/agent-brain-claude-code.md`

- [ ] **Step 1: Read current file**

```bash
cat plugins/claude-code/skills/agent-brain-claude-code.md
```

Expected: current keyword-trigger list (~33 lines)

- [ ] **Step 2: Replace with two-phase protocol**

Write the following content to `plugins/claude-code/skills/agent-brain-claude-code.md`:

```markdown
# Claude Code Memory Protocol

After EVERY response, before your next action, run the two-phase memory check.

## Phase 1 — Reflect

Ask yourself: what emerged in this conversation turn that future-you wouldn't know from reading the code or git history? Use the full conversation context — not just the last exchange. List candidates before writing any.

## Phase 2 — Category Audit (backstop)

For each category below, if Phase 1 did not already produce a candidate for it, check explicitly:

1. **Preference** — did the user state or confirm how they like things done? ("I prefer X", "I always Y", "I never Z")
2. **Correction** — did the user push back, say you were wrong, or redirect your approach?
3. **Project constraint** — did a deadline, policy, convention, or scope limit emerge?
4. **Architectural decision** — was a design choice, technology, or pattern decided or confirmed?
5. **Deferred intention** — was something identified as "do later", "follow up", or "remind me"?

Skip a category if nothing genuinely new emerged for it this turn.

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

**Category 5 → set_intention:**

- content: what to do
- topic: short label for the deferred task

## PROJECT SKILLS — when user codifies a reusable rule:
- "always use X pattern in this repo", project convention → ingest_skill(name, body, description)
- Use for agent instructions, NOT preference facts (those go to memory_write)

## DO NOT WRITE:
- Routine code edits, file reads, implementation steps
- "ok", "thanks", "looks good", boilerplate confirmations
- Facts already in recalled context that have not changed
```

- [ ] **Step 3: Verify file is correct**

```bash
wc -l plugins/claude-code/skills/agent-brain-claude-code.md
grep -n "Phase 1\|Phase 2\|Category Audit" plugins/claude-code/skills/agent-brain-claude-code.md
```

Expected: ~48 lines, both phase headings present

- [ ] **Step 4: Commit**

```bash
git add plugins/claude-code/skills/agent-brain-claude-code.md
git commit -m "feat(claude-code): replace keyword triggers with two-phase memory protocol in SKILL.md"
```

---

## Task 2: Simplify Claude Code index.sh + delete heuristic

**Files:**
- Modify: `plugins/claude-code/scripts/index.sh`
- Delete: `plugins/claude-code/scripts/lib/index-heuristic.sh`

- [ ] **Step 1: Read current index.sh**

```bash
cat plugins/claude-code/scripts/index.sh
```

Expected: ~58 lines; sources `index-heuristic.sh`; has candidate loop at lines 31–55

- [ ] **Step 2: Replace index.sh with completion-only version**

Write the following content to `plugins/claude-code/scripts/index.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

input=$(cat)
sid=$(echo "$input" | jq -r '.session_id // empty')
[[ -n "$sid" ]] && export NIGHTHAWK_SESSION_ID="agent-brain-${sid}"
rm -f "$(agent_brain_last_prompt_file)" 2>/dev/null || true

# Complete intentions that were triggered (and acted on) during this session.
# IDs are written by recall.sh whenever check_intentions returns triggered status.
triggered_file="/tmp/agent-brain-triggered-intentions-${NIGHTHAWK_SESSION_ID:-default}"
if [[ -f "$triggered_file" && -s "$triggered_file" ]]; then
  while IFS= read -r intention_id; do
    [[ -z "$intention_id" ]] && continue
    args=$(jq -nc \
      --arg aid "${NIGHTHAWK_AGENT_ID:-}" \
      --arg iid "$intention_id" \
      '{agent_id:$aid, intention_id:$iid}')
    agent_brain_mcp_call complete_intention "$args" >/dev/null 2>&1 || true
  done < "$triggered_file"
  rm -f "$triggered_file" 2>/dev/null || true
fi

echo '{}'
exit 0
```

- [ ] **Step 3: Delete the heuristic file**

```bash
git rm plugins/claude-code/scripts/lib/index-heuristic.sh
```

- [ ] **Step 4: Verify index.sh has no heuristic references**

```bash
grep -n "index-heuristic\|indexCandidates\|agent_brain_index_candidates" plugins/claude-code/scripts/index.sh
```

Expected: no output (grep returns nothing)

- [ ] **Step 5: Smoke-test the script parses valid JSON**

```bash
echo '{"session_id":"test-123"}' | bash plugins/claude-code/scripts/index.sh
```

Expected: `{}`

- [ ] **Step 6: Commit**

```bash
git add plugins/claude-code/scripts/index.sh
git commit -m "feat(claude-code): simplify Stop hook to intention-completion-only, remove heuristic"
```

---

## Task 3: Rewrite Cursor SKILL.md

**Files:**
- Modify: `plugins/cursor/skills/agent-brain-cursor.md`

- [ ] **Step 1: Read current file**

```bash
cat plugins/cursor/skills/agent-brain-cursor.md
```

Expected: identical content to the old Claude Code skill file (~33 lines)

- [ ] **Step 2: Replace with two-phase protocol**

Write the following content to `plugins/cursor/skills/agent-brain-cursor.md`:

```markdown
# Cursor Memory Protocol

After EVERY response, before your next action, run the two-phase memory check.

## Phase 1 — Reflect

Ask yourself: what emerged in this conversation turn that future-you wouldn't know from reading the code or git history? Use the full conversation context — not just the last exchange. List candidates before writing any.

## Phase 2 — Category Audit (backstop)

For each category below, if Phase 1 did not already produce a candidate for it, check explicitly:

1. **Preference** — did the user state or confirm how they like things done? ("I prefer X", "I always Y", "I never Z")
2. **Correction** — did the user push back, say you were wrong, or redirect your approach?
3. **Project constraint** — did a deadline, policy, convention, or scope limit emerge?
4. **Architectural decision** — was a design choice, technology, or pattern decided or confirmed?
5. **Deferred intention** — was something identified as "do later", "follow up", or "remind me"?

Skip a category if nothing genuinely new emerged for it this turn.

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

**Category 5 → set_intention:**

- content: what to do
- topic: short label for the deferred task

## PROJECT SKILLS — when user codifies a reusable rule:
- "always use X pattern in this repo", project convention → ingest_skill(name, body, description)
- Use for agent instructions, NOT preference facts (those go to memory_write)

## DO NOT WRITE:
- Routine code edits, file reads, implementation steps
- "ok", "thanks", "looks good", boilerplate confirmations
- Facts already in recalled context that have not changed
```

- [ ] **Step 3: Verify**

```bash
grep -n "Phase 1\|Phase 2\|Category Audit" plugins/cursor/skills/agent-brain-cursor.md
```

Expected: both phase headings present

- [ ] **Step 4: Commit**

```bash
git add plugins/cursor/skills/agent-brain-cursor.md
git commit -m "feat(cursor): replace keyword triggers with two-phase memory protocol in SKILL.md"
```

---

## Task 4: Simplify Cursor index.sh + delete heuristic

**Files:**
- Modify: `plugins/cursor/hooks/index.sh`
- Delete: `plugins/cursor/hooks/lib/index-heuristic.sh`

- [ ] **Step 1: Read current index.sh**

```bash
cat plugins/cursor/hooks/index.sh
```

Expected: ~60 lines; sources `index-heuristic.sh`; has candidate loop at lines 33–57

- [ ] **Step 2: Replace index.sh with completion-only version**

Write the following content to `plugins/cursor/hooks/index.sh`:

```bash
#!/usr/bin/env bash
# afterAgentResponse / stop: complete triggered intentions.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
agent_brain_load_env || true

input=$(cat)
existing="$(agent_brain_load_session || true)"
[[ -n "$existing" ]] && export NIGHTHAWK_SESSION_ID="$existing"

# Complete intentions that were triggered (and acted on) during this session.
# IDs are written by recall.sh / session-start.sh whenever check_intentions returns triggered status.
triggered_file="/tmp/agent-brain-triggered-intentions-${NIGHTHAWK_SESSION_ID:-default}"
if [[ -f "$triggered_file" && -s "$triggered_file" ]]; then
  while IFS= read -r intention_id; do
    [[ -z "$intention_id" ]] && continue
    args=$(jq -nc \
      --arg aid "${NIGHTHAWK_AGENT_ID:-}" \
      --arg iid "$intention_id" \
      '{agent_id:$aid, intention_id:$iid}')
    agent_brain_mcp_call complete_intention "$args" >/dev/null 2>&1 || true
  done < "$triggered_file"
  rm -f "$triggered_file" 2>/dev/null || true
fi

echo '{}'
exit 0
```

- [ ] **Step 3: Delete the heuristic file**

```bash
git rm plugins/cursor/hooks/lib/index-heuristic.sh
```

- [ ] **Step 4: Verify no heuristic references remain**

```bash
grep -n "index-heuristic\|agent_brain_index_candidates" plugins/cursor/hooks/index.sh
```

Expected: no output

- [ ] **Step 5: Smoke-test**

```bash
echo '{}' | bash plugins/cursor/hooks/index.sh
```

Expected: `{}`

- [ ] **Step 6: Commit**

```bash
git add plugins/cursor/hooks/index.sh
git commit -m "feat(cursor): simplify Stop hook to intention-completion-only, remove heuristic"
```

---

## Task 5: Rewrite OpenClaw SKILL.md

**Files:**
- Modify: `plugins/openclaw/skills/agent-brain-openclaw.md`

- [ ] **Step 1: Read current file**

```bash
cat plugins/openclaw/skills/agent-brain-openclaw.md
```

Expected: ~33 lines, keyword-trigger list

- [ ] **Step 2: Replace with two-phase protocol**

Write the following content to `plugins/openclaw/skills/agent-brain-openclaw.md`:

```markdown
# OpenClaw Memory Protocol

After EVERY response, before your next action, run the two-phase memory check.

## Phase 1 — Reflect

Ask yourself: what emerged in this conversation turn that future-you wouldn't know from reading the code or git history? Use the full conversation context — not just the last exchange. List candidates before writing any.

## Phase 2 — Category Audit (backstop)

For each category below, if Phase 1 did not already produce a candidate for it, check explicitly:

1. **Preference** — did the user state or confirm how they like things done? ("I prefer X", "I always Y", "I never Z")
2. **Correction** — did the user push back, say you were wrong, or redirect your approach?
3. **Project constraint** — did a deadline, policy, convention, or scope limit emerge?
4. **Architectural decision** — was a design choice, technology, or pattern decided or confirmed?
5. **Deferred intention** — was something identified as "do later", "follow up", or "remind me"?

Skip a category if nothing genuinely new emerged for it this turn.

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

**Category 5 → set_intention:**

- content: what to do
- topic: short label for the deferred task

## PROJECT SKILLS — when user codifies a reusable rule:
- "always use X pattern in this repo", project convention → ingest_skill(name, body, description)
- Use for agent instructions, NOT preference facts (those go to memory_write)

## DO NOT WRITE:
- Routine code edits, file reads, implementation steps
- "ok", "thanks", "looks good", boilerplate confirmations
- Facts already in recalled context that have not changed
```

- [ ] **Step 3: Verify**

```bash
grep -n "Phase 1\|Phase 2\|Category Audit" plugins/openclaw/skills/agent-brain-openclaw.md
```

Expected: both phase headings present

- [ ] **Step 4: Commit**

```bash
git add plugins/openclaw/skills/agent-brain-openclaw.md
git commit -m "feat(openclaw): replace keyword triggers with two-phase memory protocol in SKILL.md"
```

---

## Task 6: Simplify OpenClaw capture.ts + clean format.ts

**Files:**
- Modify: `plugins/openclaw/capture.ts`
- Modify: `plugins/openclaw/format.ts`

- [ ] **Step 1: Read current capture.ts**

```bash
cat plugins/openclaw/capture.ts
```

Expected: ~80 lines; Phase 2 at lines 53–76 calls `indexCandidates()` and loops over candidates

- [ ] **Step 2: Replace capture.ts with completion-only version**

Write the following content to `plugins/openclaw/capture.ts`:

```typescript
import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { resolveAgentId } from "./config.js";
import type { PluginApi } from "./recall.js";
import { loadAndClearTriggeredIntentionIds } from "./session-state.js";

export type AgentEndCtx = {
  sessionKey?: string;
  trigger?: string;
  messages?: Array<{ role?: string; content?: string }>;
};

export function createCaptureHook(api: PluginApi, cfg: AgentBrainPluginConfig) {
  return async (ctx: AgentEndCtx) => {
    if (ctx.trigger === "memory") return {};
    if (ctx.sessionKey?.includes(":memory-capture:")) return {};

    const agentId = resolveAgentId(cfg, ctx.sessionKey);

    // Complete intentions that were triggered (and acted on) during this session.
    const triggeredIds = await loadAndClearTriggeredIntentionIds(ctx.sessionKey);
    for (const id of triggeredIds) {
      try {
        await callMcpTool(
          cfg,
          api.rootDir,
          "complete_intention",
          { agent_id: agentId, intention_id: id },
          ctx.sessionKey,
        );
      } catch (err) {
        api.logger.warn(`agent-brain: complete_intention failed: ${String(err)}`);
      }
    }

    return {};
  };
}
```

- [ ] **Step 3: Read current format.ts**

```bash
cat plugins/openclaw/format.ts
```

Expected: ~135 lines; regex constants at lines 68–78; `WriteCandidate` type at lines 80–88; `indexCandidates()` at lines 90–134

- [ ] **Step 4: Remove regex constants, WriteCandidate type, and indexCandidates() from format.ts**

Delete lines 68–134 (everything from `const PREFERENCE_RE` through the closing `}` of `indexCandidates`). The file should end after `extractTriggeredIds` (line 66).

The resulting `plugins/openclaw/format.ts` should be:

```typescript
export type MemoryRow = {
  subject_raw?: string;
  SubjectRaw?: string;
  content?: string;
  Content?: string;
  confidence?: number;
  Confidence?: number;
};

export function formatRecallBlock(rows: MemoryRow[], maxItems: number): string {
  const list = Array.isArray(rows) ? rows : (rows as { memories?: MemoryRow[] }).memories ?? [];
  const slice = list.slice(0, maxItems);
  if (slice.length === 0) return "";

  const lines = slice.map((m) => {
    const subj = m.subject_raw ?? m.SubjectRaw ?? "fact";
    const content = m.content ?? m.Content ?? "";
    const conf = m.confidence ?? m.Confidence ?? 0.8;
    return `- [${subj}] ${content} (conf ${conf})`;
  });

  return [
    "<untrusted-data agent-brain>",
    "## Memory context (agent-brain)",
    ...lines,
    "</untrusted-data>",
  ].join("\n");
}

export type IntentionRow = {
  id?: string;
  ID?: string;
  topic?: string;
  content?: string;
  status?: string;
};

function parseIntentions(raw: string): IntentionRow[] {
  try {
    const parsed: unknown = JSON.parse(raw);
    if (Array.isArray(parsed)) return parsed as IntentionRow[];
    if (parsed !== null && typeof parsed === "object") {
      const p = parsed as Record<string, unknown>;
      if (Array.isArray(p.intentions)) return p.intentions as IntentionRow[];
    }
  } catch {
    // ignore
  }
  return [];
}

export function formatIntentionsBlock(raw: string): string {
  const intentions = parseIntentions(raw).filter(
    (i) => i.status === "pending" || i.status === "triggered",
  );
  if (intentions.length === 0) return "";
  const lines = intentions.map((i) => `- [intention: ${i.topic ?? "task"}] ${i.content ?? ""}`);
  return ["## Pending intentions", ...lines].join("\n");
}

export function extractTriggeredIds(raw: string): string[] {
  return parseIntentions(raw)
    .filter((i) => i.status === "triggered")
    .map((i) => i.id ?? i.ID ?? "")
    .filter(Boolean);
}
```

- [ ] **Step 5: Verify indexCandidates is fully removed**

```bash
grep -n "indexCandidates\|WriteCandidate\|CORRECTION_RE\|DEFERRED_RE\|PREFERENCE_RE\|CONSTRAINT_RE\|DECISION_RE\|BOILERPLATE_RE" \
  plugins/openclaw/format.ts plugins/openclaw/capture.ts
```

Expected: no output

- [ ] **Step 6: Verify capture.ts no longer imports indexCandidates or loadLastUserPrompt**

```bash
grep -n "indexCandidates\|loadLastUserPrompt\|indexCandidates" plugins/openclaw/capture.ts
```

Expected: no output

- [ ] **Step 7: Type-check**

```bash
cd plugins/openclaw && npx tsc --noEmit 2>&1 | head -20
```

Expected: no errors (or pre-existing errors unrelated to these files)

- [ ] **Step 8: Commit**

```bash
git add plugins/openclaw/capture.ts plugins/openclaw/format.ts
git commit -m "feat(openclaw): simplify capture hook to intention-completion-only, remove heuristic"
```

---

## Task 7: Update design specs

**Files:**
- Modify: `docs/superpowers/specs/2026-06-04-claude-code-plugin-design.md`
- Modify: `docs/superpowers/specs/2026-06-05-skill-layer-memory-design.md`

- [ ] **Step 1: Update index.sh row in claude-code plugin design**

In `docs/superpowers/specs/2026-06-04-claude-code-plugin-design.md`, find the row describing `index.sh` in the hook catalog table and update its description to reflect completion-only behavior.

Find the line containing `index.sh` in the hooks table and change the description from anything mentioning "heuristic", "candidates", or "memory_write" to:

```
Completion-only: reads triggered-intentions file → complete_intention per ID → deletes file. No new writes.
```

- [ ] **Step 2: Verify the change**

```bash
grep -A2 "index.sh" docs/superpowers/specs/2026-06-04-claude-code-plugin-design.md | grep -i "completion\|complete"
```

Expected: matches the updated row

- [ ] **Step 3: Update skill-layer-memory design**

In `docs/superpowers/specs/2026-06-05-skill-layer-memory-design.md`:

a. Find the "after-each-response protocol" section and replace its content with:

```markdown
### After-Each-Response Protocol

The agent runs a two-phase check after every response:

**Phase 1 — Open reflection:** The agent considers the full conversation context and identifies what emerged that wouldn't be derivable from code or git history.

**Phase 2 — Category audit (backstop):** Five explicit checks — preference, correction, project constraint, architectural decision, deferred intention — catch anything Phase 1 missed.

Write routing: categories 1–4 → `memory_write`; category 5 → `set_intention`. Confidence anchored to evidence quality (0.90–0.95 explicit, 0.80 confirmed, 0.65–0.75 inferred).
```

b. Find and remove any section or table describing heuristic tiers (Tier 1–5 regex matching).

- [ ] **Step 4: Verify heuristic tiers table is removed**

```bash
grep -n "Tier [1-5]\|tier-[1-5]\|index-heuristic\|CORRECTION_RE\|PREFERENCE_RE" \
  docs/superpowers/specs/2026-06-05-skill-layer-memory-design.md
```

Expected: no output

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-06-04-claude-code-plugin-design.md \
        docs/superpowers/specs/2026-06-05-skill-layer-memory-design.md
git commit -m "docs: update plugin design specs to reflect completion-only Stop hooks"
```

---

## Self-Review Checklist (for implementer)

After all tasks are complete, verify:

- [ ] `grep -r "index-heuristic\|agent_brain_index_candidates\|indexCandidates" plugins/` returns no output
- [ ] `grep -r "Phase 1\|Phase 2\|Category Audit" plugins/*/skills/` shows all three SKILL.md files
- [ ] `echo '{}' | bash plugins/claude-code/scripts/index.sh` returns `{}`
- [ ] `echo '{}' | bash plugins/cursor/hooks/index.sh` returns `{}`
- [ ] `cd plugins/openclaw && npx tsc --noEmit` passes
