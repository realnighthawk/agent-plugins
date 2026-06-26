# Skill: Memory Consistency

# memory-consistency / SKILL.md

## Purpose

This skill ensures that the model maintains **coherent, stable, and non-contradictory behavior over time** when using memory.

It governs how memory is:
- interpreted
- applied
- updated

The goal is to prevent:
- drift
- contradiction
- overfitting
- stale behavior

---

## Core Principle

> Memory should create **consistency over time**, not rigidity or error propagation.

---

## Consistency Layers

The model must maintain consistency across three layers:

### 1. Within a single response
- no contradictions between memory and output
- consistent tone and assumptions

### 2. Across a session
- stable behavior during the conversation
- no flip-flopping unless corrected

### 3. Across sessions (via memory)
- long-term patterns should feel continuous
- preferences should persist unless updated

---

## Using Memory Consistently

### 1. Prefer stable signals

When memory contains repeated or high-confidence signals:

- treat them as stronger guidance
- prioritize over weak or ambiguous signals

Example:

- multiple signals → "user prefers concise answers"
→ consistently keep responses concise

---

### 2. Handle weak signals carefully

If memory confidence is low:

- treat as a soft suggestion
- avoid strong assumptions
- do not overcommit

---

### 3. Avoid overfitting

Do NOT:

- blindly apply memory to every response
- force irrelevant preferences into context
- generalize too broadly from limited data

---

## Conflict Resolution Rules

### Rule 1 — User overrides memory

If the user explicitly contradicts memory:

> ALWAYS prioritize the current user input

Example:

Memory: user prefers vegetarian food  
User: "Recommend a steak recipe"

→ Follow current request without resistance

---

### Rule 2 — Recent > old

If memory appears outdated:

- favor recent behavior or statements
- treat older memory as lower priority

---

### Rule 3 — Explicit > inferred

Explicitly stated preferences:
- higher priority

Inferred behavior:
- lower priority

---

### Rule 4 — Context relevance

Only apply memory if it is relevant to the task

Example:

- workout preference → irrelevant for coding question

---

## Updating Consistency (via memory_write)

When new information appears:

### Write when:
- preference is clearly expressed
- behavior repeats
- constraint is explicitly stated

### Do NOT write when:
- signal is ambiguous
- one-off request
- temporary context

---

## Preventing Contradictions

The model MUST NOT:

### 1. Contradict stored preferences

❌ "You prefer short answers" → gives long essay

---

### 2. Flip behavior without reason

❌ concise → verbose → concise randomly

---

### 3. Ignore constraints

❌ memory: "no dairy"  
→ suggests cheese-heavy meals

---

## Gradual Adaptation

Memory updates should feel:

- smooth
- progressive
- natural

NOT:

- sudden
- extreme
- inconsistent

---

## Confidence-Aware Behavior

Use confidence from `memory_search` EMU fields when available:

| Signal | Source field | Behavior |
|--------|--------------|----------|
| High   | `activation_score` ≥ 0.7, or high `salience` + `reinforcement_score` | Apply strongly |
| Medium | Moderate scores | Apply softly |
| Low    | Low scores or few supporting EMUs | Consider but verify |

---

## Recovery from Inconsistency

If inconsistency occurs:

- align immediately with current user input
- avoid referencing past inconsistency
- continue with corrected behavior

---

## Anti-Patterns

### ❌ Rigid behavior

> Always enforcing memory even when irrelevant

---

### ❌ Memory dominance

> Letting memory override user intent

---

### ❌ Pattern hallucination

> Assuming preferences from insufficient data

---

### ❌ Stale persistence

> Continuing outdated behavior despite new signals

---

## Correct Behavior Pattern

### ✔ Good

> "Since you usually prefer quick answers, here's a short summary."

- relevant
- soft application
- non-blocking

---

### ✔ Good

> User changes preference → model adapts immediately

---

## Tone Guidelines

- Subtle integration of memory
- Avoid explicit references to "stored memory"
- Keep responses natural

---

## Key Takeaway

> Consistency is about **alignment over time**, not rigid repetition.

The model should:
- stay stable
- adapt when needed
- prioritize the present
- use memory as guidance, not control