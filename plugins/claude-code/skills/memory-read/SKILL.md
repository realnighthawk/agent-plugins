# Skill: Memory Search (`memory_search`)

## Purpose

This skill defines how the model MUST use the `memory_search` tool to retrieve and apply contextual memory.

The memory system is an external hippocampal service that returns **activation-scored episodic memory units (EMUs)** assembled into working memory.

The model MUST treat outputs as authoritative context inputs, not raw data.

> **Not `search_event_context`:** That tool looks up existing entity/predicate vocabulary before writing. Use it only as a pre-write step (see memory-write skill). Use `memory_search` for recall.

---

## When to use `memory_search`

Call `memory_search` when the response depends on any of the following:

### 1. Personalization needs
- user preferences may affect response
- tone, style, or recommendations should adapt
- prior behavior influences current advice

### 2. Planning or decision-making
- generating plans, schedules, or strategies
- recommending actions or workflows
- prioritizing options for the user

### 3. Long-term context relevance
- user refers to past behavior or decisions
- continuity across sessions is needed
- repeated topics appear across conversation history

### 4. Constraint enforcement
- known user constraints must be respected
- habitual behaviors affect recommendations

---

## When NOT to use `memory_search`

Do NOT call `memory_search` when:

- the request is purely factual or general knowledge
- no personalization or past context is relevant
- the task is self-contained within the current turn
- memory would not materially change the response
- you only need canonical entity/predicate IDs before a write (use `search_event_context` instead)

---

## Core Principle

> Memory is a contextual biasing layer, not a database to be exhaustively queried.

Only retrieve memory when it improves decision quality.

---

## Request Format

`memory_search` accepts a natural-language query and an optional result limit. Tenant context (`user_id`, `agent_id`) is resolved from MCP auth — do not pass them unless required by your integration.

```json
{
  "query": "<natural language query describing what context you need>",
  "limit": 10
}
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `query` | yes | Natural-language recall query (e.g. `"food preferences"`, `"fitness routine"`, `"agent-brain architecture decisions"`) |
| `limit` | no | Max EMUs to return (default 10) |

There are no `filters`, `context`, `time_range`, `event_type`, or `topic` parameters on this tool. Encode scope in the query string itself (e.g. `"recent workout preferences"`).

---

## Response Format

The tool returns a `MemoryAssembly` — working memory produced by the EMU recall pipeline:

```json
{
  "query_hash": "<hash of query>",
  "emus": [
    {
      "id": "<uuid>",
      "episode_cluster_id": "<cluster>",
      "support_count": 3,
      "activation_score": 0.82,
      "salience": 0.7,
      "reinforcement_score": 0.6,
      "stability_score": 0.5,
      "temporal_bucket": "morning",
      "frequency": 0.3,
      "cosine_score": 0.91
    }
  ],
  "context_tags": ["morning", "fitness"],
  "duration_ms": 42
}
```

EMUs are pre-ranked by `activation_score`. Higher scores mean stronger relevance for the current query.

---

## How to Use Memory Output

### 1. Treat as authoritative context
- Do NOT reinterpret internal EMU structure or infer how clusters were formed
- Do NOT assume missing memory implies absence of behavior
- Do NOT reconstruct graph, embedding, or clustering logic

### 2. Use as behavioral bias input

Memory influences:
- tone selection
- recommendation ranking
- plan structure
- constraint filtering

Use `activation_score`, `salience`, and `reinforcement_score` as confidence hints — higher values warrant stronger bias.

### 3. Resolve conflicts carefully

If memory conflicts with current user input:
- prioritize explicit user statements
- treat memory as prior, not override
- update behavior cautiously (via `memory_write`, not `memory_search`)

### 4. Do NOT overfit memory

Avoid:
- rigidly following outdated preferences
- assuming memory is always up-to-date
- ignoring new explicit corrections

Memory is probabilistic bias, not absolute truth.

---

## Timing Rule

Call `memory_search`:
- BEFORE generating personalized responses
- NOT after response generation
- NOT repeatedly in the same reasoning chain unless context changes

---

## System Boundary Rule

This skill does NOT:
- interpret or construct EMUs
- perform retrieval ranking
- modify memory content
- simulate memory system logic
- reconstruct internal clustering or graphs

It ONLY defines how to request and use memory context.

---

## Key Principle

`memory_search` returns a ranked EMU assembly, not raw event history.

The memory system handles:
- EMU formation
- clustering
- activation scoring
- consolidation

The model only consumes the result.
