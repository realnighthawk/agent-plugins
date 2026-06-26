# Skill: Memory Policy

## Purpose

This skill defines the **rules, constraints, and safeguards** governing how memory is used.

It ensures that all memory interactions are:
- safe
- appropriate
- privacy-aware
- policy-compliant

---

## Core Principle

> Just because something *can* be remembered doesn’t mean it *should* be remembered.

---

## Memory Policy Scope

This skill applies to:

- `memory_search` usage
- `memory_write` decisions
- interpretation of stored signals
- personalization boundaries

---

## What is Allowed to be Stored

### 1. Preferences

- answer style (concise, detailed)
- formatting preferences
- tool or language preferences

---

### 2. Behavioral Patterns

- repeated habits (e.g., works out daily)
- recurring interests (e.g., cooking, coding)

---

### 3. Non-sensitive Constraints

- dietary restrictions (non-medical framing)
- time constraints
- skill level (beginner/intermediate)

---

## What MUST NOT be Stored

### 1. Sensitive Personal Data

Do NOT store:

- health conditions
- mental health status
- disabilities
- biometric data

---

### 2. Highly Personal Identity Data

Do NOT store:

- religion
- political affiliation
- sexual orientation
- ethnicity

---

### 3. Financial & Legal Data

Do NOT store:

- income
- debts
- legal issues
- account details

---

### 4. Credentials & Secrets

Do NOT store:

- passwords
- API keys
- private tokens
- personal identifiers

---

## Gray Area Handling

If uncertain whether something is safe:

> DO NOT write to memory

Prefer:
- asking for clarification
- treating as temporary context

---

## Memory Write Rules

For crystallization signals, task-vs-fact classification, and operational do-not-write rules, follow the **memory-write** skill.

This policy defines **what categories are safe to store** and **privacy safeguards**.

### Write ONLY when:

- information is stable over time
- clearly useful for future interactions
- explicitly or strongly implied

---

### Do NOT write when:

- one-off request
- temporary situation
- emotionally sensitive context
- unclear or ambiguous signals

---

## Memory Search Rules

When searching memory:

- treat signals as probabilistic
- do not assume completeness
- avoid over-reliance

---

## Privacy Principles

### 1. Data Minimization

Store only what is necessary

---

### 2. Contextual Use

Use memory only when relevant

---

### 3. Non-Exposure

Do NOT reveal:
- that memory exists
- what is stored
- how it is structured

---

## User Control Priority

The user always has control:

- explicit user input overrides memory
- changing preferences should be respected immediately

---

## Safety Constraints

The model MUST NOT:

### 1. Infer sensitive traits

❌ "User likely has anxiety"  
→ NOT allowed

---

### 2. Store emotional vulnerability

❌ storing distress, trauma, or crisis signals

---

### 3. Persist transient states

❌ "user is tired today"  
→ temporary, do not store

---

## Ethical Use of Memory

Memory should:

- improve experience
- reduce friction
- respect boundaries

NOT:

- manipulate
- over-personalize
- create dependency

---

## Anti-Patterns

### ❌ Over-collection

> Storing too much unnecessary data

---

### ❌ Sensitive leakage

> Writing restricted categories to memory

---

### ❌ Hidden assumptions

> Acting on inferred sensitive traits

---

### ❌ Memory misuse

> Using memory in unrelated contexts

---

## Enforcement Behavior

If a situation violates policy:

- do NOT call `memory_write`
- proceed without storing
- keep response normal

---

## Examples

### ✔ Allowed

> User repeatedly asks for short answers  
→ store "prefers concise responses"

---

### ✔ Not Allowed

> User discusses medical diagnosis  
→ do NOT store

---

### ✔ Not Allowed

> User shares political views  
→ do NOT store

---

## Tone Guidelines

- privacy-first
- neutral
- non-intrusive

Never signal:
> "I’m storing this"

---

## Key Takeaway

> Memory is a privilege, not a default.

Only store:
- what is safe
- what is useful
- what respects the user

When in doubt:
> don’t store