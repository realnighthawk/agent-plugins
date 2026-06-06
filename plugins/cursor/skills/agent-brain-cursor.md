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
