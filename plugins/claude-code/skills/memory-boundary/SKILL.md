# Skill: Memory Boundary

## Purpose

This skill defines the **strict boundary** between the model and the memory system.

It ensures the model:
- does NOT simulate internal memory mechanisms
- does NOT invent memory structure
- does NOT overreach beyond provided memory outputs

This skill is critical for maintaining **architectural separation**.

---

## Core Principle

> The model is a **consumer of memory**, not a **builder of memory systems**.

---

## What the Model CAN Do

The model is allowed to:

### 1. Call memory tools
- `memory_search` → retrieve activation-scored EMUs
- `memory_write` → persist new information

---

### 2. Use returned memory context

The model may:
- adapt tone, style, and recommendations
- apply preferences and constraints
- bias decision-making using memory signals

---

### 3. Reason over summaries

The model may:
- use `context_tags` and high-scoring EMUs as contextual signals
- apply preferences, behaviors, and constraints implied by returned EMUs
- combine memory with current user input

---

## What the Model MUST NOT Do

### 1. NO EMU simulation

Do NOT:
- define or construct EMUs (Event Memory Units)
- simulate episodic memory formation
- invent memory encoding structures

❌ Example (forbidden):
> "I'll create an EMU representing this conversation..."

---

### 2. NO memory assembly logic

Do NOT:
- cluster events into assemblies
- simulate retrieval ranking
- merge or deduplicate memory entries

❌ Example:
> "These memories likely cluster into a pattern of..."

---

### 3. NO internal architecture reasoning

Do NOT:
- describe hippocampus-like systems
- reference vector databases, embeddings, or graphs
- speculate about memory pipelines

❌ Example:
> "The system probably stores this in a vector index..."

---

### 4. NO raw memory reconstruction

Do NOT:
- attempt to rebuild full history from summaries
- assume missing data means absence
- infer hidden memory content

---

### 5. NO direct memory mutation logic

Do NOT:
- edit or rewrite past memories
- delete or merge memory entries
- simulate consolidation or decay

Only use:
- `memory_write` to append/update

---

## Tool Responsibility Separation

| Responsibility            | Owned By        |
|--------------------------|-----------------|
| EMU creation             | Memory system   |
| Memory storage           | Memory system   |
| Clustering               | Memory system   |
| Ranking / retrieval      | Memory system   |
| Context shaping          | Memory system   |
| Final reasoning          | Model           |

---

## Interaction Model

### Step 1 — Retrieve (optional)
Use `memory_search` if context is needed

### Step 2 — Reason
Combine:
- user input
- retrieved memory context

### Step 3 — Respond
Generate answer using adapted reasoning

### Step 4 — Persist (optional)
Use `memory_write` if new durable info exists

---

## Anti-Patterns

### ❌ Overreach

> "Based on clustering these past events..."

→ The model must NOT perform clustering

---

### ❌ Architecture leakage

> "This will be stored as a long-term episodic trace..."

→ The model must NOT describe storage internals

---

### ❌ Fake memory certainty

> "You always prefer X"

→ Use probabilistic phrasing unless explicitly confirmed

---

### ❌ Memory hallucination

> Inventing preferences not present in memory_search output

---

## Correct Usage Pattern

### ✔ Good

> "You mentioned preferring short workouts, so here's a 20-minute plan."

- grounded in memory signal
- applied as soft constraint

---

### ✔ Good

> "If this is something you'd like to track long-term, I can remember it."

- defers persistence decision appropriately

---

## Tone Guidelines

When using memory:

- Be subtle, not explicit
- Avoid over-referencing "memory"
- Integrate naturally into response

---

## Boundary Enforcement Rule

If uncertain:

> DO LESS with memory, not more.

- avoid guessing
- avoid overfitting
- rely on current user input first

---

## Key Takeaway

> The model **thinks with memory**, but does NOT **simulate memory**.

Memory is:
- external
- pre-processed
- authoritative within limits

The model:
- consumes
- adapts
- responds

Nothing more.