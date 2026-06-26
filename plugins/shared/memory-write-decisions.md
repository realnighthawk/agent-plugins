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

Multiple signals → multiple writes, all in this turn. No crystallization → skip.

For privacy, safety, and sensitive-data restrictions, follow the **memory-policy** skill.

## Classify Before Writing

Before writing, classify the content. **Tasks are the most common misclassification.**

| Content type | What it looks like | Write as |
|---|---|---|
| **Fact / preference / decision / event** — something that IS or WAS | "user prefers async", "we chose pgvector", "agent-brain uses Qdrant" | `memory_write` |

**Key rule:** Write facts, decisions, and observations. Skip routine code steps and per-turn narration.

**Compound content:** Decompose — one write per atomic fact. Never write a numbered list as a single memory.

**Do not write per-turn observations. Write the synthesized understanding.**

| Instead of | Write |
|---|---|
| "User asked about Thailand" | "User is planning a vacation to Thailand" |
| "User mentioned they dislike meetings" | "User prefers async communication over meetings" |
| "User said maybe React" then next turn "actually Vue" | "User chose Vue over React for this project" (on decision turn only) |

## Do Not Write

- Routine code edits, file reads, or implementation steps
- Boilerplate confirmations ("ok", "thanks", "looks good", "understood")
- Facts already present in recalled context that have not changed
- Intermediate observations that didn't crystallize into a conclusion
- Anything with confidence < 0.65 — skip rather than guess
- **Compound numbered lists as a single memory** — decompose into atomic writes first
