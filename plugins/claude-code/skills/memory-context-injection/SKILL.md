# Skill: Memory Context Injection

## Purpose

This skill defines **how memory is injected into the model’s reasoning context** safely and effectively.

It ensures memory:
- enhances responses
- remains relevant
- does not overwhelm or distort reasoning

---

## Core Principle

> Memory should be **selectively injected context**, not a full replay of the past.

---

## What is Context Injection?

Context injection is the process where `memory_search` returns:

- activation-scored EMUs (ranked episodic memory units)
- `context_tags` summarizing the assembly
- lightweight, relevance-ranked context

The model then **integrates this into reasoning**.

---

## Injection Rules

### 1. Relevance First

Only use memory that is **directly relevant** to the current request.

✔ Use:
- diet preferences → food recommendations  
- coding stack → technical suggestions  

❌ Do NOT use:
- unrelated past topics  
- stale or irrelevant signals  

---

### 2. Minimal Necessary Context

Use the **smallest amount of memory** needed to improve the response.

Avoid:
- dumping all memory into reasoning
- over-explaining context

---

### 3. Soft Influence, Not Hard Constraints

Memory should:
- guide responses
- bias decisions

But NOT:
- override explicit user intent
- restrict valid outputs unnecessarily

---

### 4. Blend, Don’t Attach

Memory should be **naturally integrated**, not appended.

✔ Good:
> "Here’s a short version since you prefer concise answers."

❌ Bad:
> "From memory: user prefers concise answers."

---

## Injection Timing

### When to inject memory

Use `memory_search` when:

- personalization would improve the answer
- ambiguity can be resolved with past context
- preferences affect output quality

---

### When NOT to inject

Do NOT use memory when:

- task is purely factual
- no personalization benefit exists
- memory confidence is low and risky

---

## Injection Levels

### Level 1 — Light Bias

- tone adjustments
- formatting preferences

Example:
- concise vs detailed

---

### Level 2 — Decision Influence

- choosing between options
- prioritizing recommendations

Example:
- vegetarian vs non-vegetarian meals

---

### Level 3 — Constraint Application

- applying hard constraints when highly confident

Example:
- allergies
- explicit restrictions

---

## Ordering of Influence

When generating a response:

1. Current user input (highest priority)
2. Relevant memory signals
3. General knowledge

---

## Avoiding Context Pollution

The model MUST NOT:

### 1. Overload reasoning

❌ Inject too many signals → noisy output

---

### 2. Mix unrelated contexts

❌ Combining multiple unrelated preferences

---

### 3. Create false connections

❌ Inferring relationships between unrelated memories

---

## Handling Ambiguity

If memory is unclear:

- apply lightly or ignore
- prioritize user input
- avoid assumptions

---

## Handling Missing Memory

If no relevant memory is returned:

- proceed normally
- do NOT compensate by guessing

---

## Memory Freshness Awareness

Prefer:

- recent signals
- repeated patterns

Deprioritize:

- old, unused signals
- one-off behaviors

---

## Anti-Patterns

### ❌ Memory Dumping

> Including full summaries in response

---

### ❌ Forced Personalization

> Injecting irrelevant preferences into answers

---

### ❌ Hidden Assumptions

> Applying memory without clear relevance

---

### ❌ Over-constraint

> Blocking valid outputs due to weak memory signals

---

## Correct Usage Pattern

### ✔ Good

> User asks for dinner ideas  
> Memory: vegetarian  

→ Suggest vegetarian meals naturally

---

### ✔ Good

> User asks technical question  
> Memory: prefers Python  

→ Provide Python examples first

---

## Tone Guidelines

- subtle
- contextual
- invisible to the user

Memory should feel like:
> "The assistant just gets me"

NOT:
> "The assistant is referencing stored data"

---

## Key Takeaway

> Inject memory like seasoning, not like the main ingredient.

It should:
- enhance clarity
- improve relevance
- stay lightweight

Never dominate the response.