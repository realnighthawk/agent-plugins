## Write Protocol

All memories go through `memory_write` — the episodic event model. There is no separate single-fact tool.

**Step 1 — Search first.**

Before writing, call `memory_search({ query: "<what the event is about>", kinds: "entities,predicates" })`. Use the returned canonical entity names and predicate names in your payload. This prevents duplicate subjects with different names.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `query` | yes | Natural-language search (e.g. `"food preferences"`, `"agent-brain architecture"`) |
| `kinds` | no | Comma-separated: `entities`, `predicates`. Omit to search both. |
| `limit` | no | Max results per kind (default 10, max 25) |

**Step 2 — Construct the payload.**

Required fields:
- `event_id` — unique per turn: `"turn-{ISO-date}-{sequence}"` (e.g. `"turn-2026-06-23-001"`). Re-submitting the same `event_id` is a no-op.
- `trigger` — what caused the event: `{ "type": "input"|"cron"|"tool_output"|"webhook", "content": "<one-line summary>", "turn_id": "<optional>" }`
- `type` — event category: `"conversation"`, `"decision"`, `"discovery"`, `"observation"`, etc.
- `timestamp` — ISO 8601 UTC: `"2026-06-23T10:30:00Z"` (defaults to now)
- `confidence` — overall event confidence (0.70–0.95)

Optional fields:
- `participants` — actors in the event. Always include self for conversations:
  - User: `{ "id": "user", "type": "self" }`
  - Agent: `{ "id": "claude-code", "type": "agent" }` (use your actual agent_id)
- `entities` — persistent subjects referenced in facts: `{ "id": "agent-brain", "type": "product", "name": "agent-brain", "confidence": 0.95 }`. Use canonical names from `memory_search`.
- `facts` — SPO triples: `{ "subject": "agent-brain", "predicate": "uses", "object": "qdrant", "confidence": 0.95 }`. Subject/object must reference an id from `participants` or `entities`.
- `observations` — JSONB-only notes (not graph-connected): `{ "type": "note", "value": "...", "confidence": 0.8 }`
- `actions` — audit trail: `{ "type": "code-change", "id": "optional-ref" }`

**Entity type guidance:**

Use one of the 5 root types. Entity types are auto-created at write time — no pre-registration needed.

| What you're writing about | entity_type |
|---|---|
| A human individual | `person` |
| An AI agent | `person` |
| A company, institution, or group | `organization` |
| A city, country, or physical/virtual place | `location` |
| A software tool, repo, system, or product | `product` |
| An abstract idea, topic, domain, or methodology | `concept` |

`concept` is the correct default for anything abstract. If you encounter a kind of thing that doesn't fit any root type, pass any descriptive string — the server will auto-create it and dreaming will normalize it later.

**Confidence guidance:**

| Trigger | `confidence` |
|---------|--------------|
| User stated explicitly | 0.90–0.95 |
| User confirmed when asked | 0.80–0.85 |
| Synthesized across multiple turns | 0.70–0.80 |
| Inferred from implicit context | 0.65–0.75 |
| Fact derived from tool/API output | 0.85–0.90 |
| Ground-truth / authoritative | 0.95–1.0 |

**Example — recording a code decision:**

```json
{
  "event_id": "turn-2026-06-23-001",
  "type": "decision",
  "timestamp": "2026-06-23T10:30:00Z",
  "participants": [
    { "id": "user", "type": "self" },
    { "id": "claude-code", "type": "agent" }
  ],
  "trigger": {
    "type": "input",
    "content": "Removed memory_write, renamed memory_write_event to memory_write"
  },
  "entities": [
    { "id": "agent-brain", "type": "product", "name": "agent-brain", "confidence": 0.95 }
  ],
  "facts": [
    { "subject": "agent-brain", "predicate": "uses", "object": "episodic-event-model", "confidence": 0.95 }
  ],
  "confidence": 0.95
}
```

**Single-entity fact** (no participants needed):

```json
{
  "event_id": "turn-2026-06-23-002",
  "type": "observation",
  "timestamp": "2026-06-23T10:31:00Z",
  "trigger": { "type": "input", "content": "User prefers async communication" },
  "entities": [
    { "id": "nighthawk", "type": "person", "name": "nighthawk", "confidence": 0.95 }
  ],
  "facts": [
    { "subject": "nighthawk", "predicate": "prefers", "object": "async-communication", "confidence": 0.92 }
  ],
  "confidence": 0.92
}
```

**Auto-creation rules:**
- Entities, predicates, and entity_types are upserted automatically — no pre-registration needed.
- Entity names are normalized to kebab-case automatically.
- `type: "self"` participants resolve to the authenticated user's entity.
