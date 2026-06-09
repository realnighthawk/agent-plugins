# Historical Memory Replay — Design Spec

**Goal:** Retroactively build agent-brain memory from historical Claude Code conversations stored in `~/.claude/projects/`, so that the memory system reflects the full knowledge accumulated across all prior sessions.

**Architecture:** Three sequential phases — extract clean transcripts, extract memories via LLM subagents, verify and resolve. All extracted memories are written under a dedicated `claude-code-replay` agent ID so they are distinguishable from live memories and can be audited or purged independently.

**Tech Stack:** Python 3 (extraction script), Claude Code subagents with agent-brain MCP, entity taxonomy (entity_type + concept pattern).

---

## Scope

**Conversations to process** (by project directory, highest signal first):

| Project | Why |
|---|---|
| `agent-brain` | Architecture decisions, design principles, migration choices |
| `superpowers` | Workflow preferences, dev process, tooling choices |
| `infra` | Infrastructure constraints, k8s choices, deployment policy |
| `superclaw` / `infra-openclaw` | Product decisions, integration patterns |
| `agent-plugins` | Plugin design, agent protocol decisions |
| `ferrosa` / `career-ops` | User-level facts, goals, personal context |
| `-Users-abishekkumar` (root) | Any top-level personal facts |

**Skip:** `superagents`, `memory-superagents`, `cognee` — early exploratory experiments with low crystallised signal.

**Memory types to extract:**
- Stated preferences and working style
- Architectural and technology decisions
- Project constraints and scope limits
- Personal facts about the user (nighthawk)
- Corrections (what approach was rejected and why)

**Do not extract:** routine code edits, file reads, test runs, debugging steps, implementation details that are already reflected in the current codebase.

---

## Phase 1 — Transcript Extraction Script

**Output:** `~/.claude/replay/transcripts/{project}/{YYYY-MM-DD}-{uuid8}.txt` per conversation + `~/.claude/replay/manifest.json`

### Script: `~/.claude/scripts/extract_conversations.py`

**Input:** All `*.jsonl` files under `~/.claude/projects/` (top-level only — skip `subagents/` subdirectories, which are implementation noise).

**Message types to process:**

| JSONL `type` | Action |
|---|---|
| `user` | Extract `message.content` as USER turn |
| `assistant` | Extract `message.content` as ASSISTANT turn (see content rules below) |
| anything else | Skip |

**Content extraction rules for assistant turns:**

The `message.content` field is an array of content blocks. Apply these rules per block:

| Block type | Rule |
|---|---|
| `text` | Keep verbatim |
| `tool_use` where name contains `Read`, `Bash`, `Grep`, `Find`, `Write`, `Edit` | Replace with `[tool: {name}]` — one line, discard input/output |
| `tool_use` where name is `Agent` | Replace with `[subagent dispatched]` |
| `tool_use` — any other | Keep `name` and `input` as `[tool: {name} {input_summary}]` |
| `tool_result` | Skip entirely |

**Content extraction rules for user turns:**

User content is usually a string. Keep verbatim. Exception: if content contains `<system-reminder>` or `<local-command-stdout>` blocks, strip them — they are injected context, not user words.

**Noise threshold:** Skip an entire conversation if it contains fewer than 3 user turns — these are trivial sessions with no extractable signal.

**Output format per transcript file:**

```
PROJECT: agent-brain
DATE: 2026-06-07
CONVERSATION: 29e0cd67

---

USER: [message text]

ASSISTANT: [message text, tool calls compressed]

USER: [message text]

ASSISTANT: [message text]

...
```

**Manifest format (`manifest.json`):**

```json
[
  {
    "project": "agent-brain",
    "date": "2026-06-07",
    "uuid": "29e0cd67-...",
    "transcript": "~/.claude/replay/transcripts/agent-brain/2026-06-07-29e0cd67.txt",
    "user_turns": 42,
    "estimated_tokens": 8400,
    "processed": false
  },
  ...
]
```

Sort manifest by `date` ascending — chronological processing ensures later decisions correctly supersede earlier ones.

---

## Phase 2 — LLM Memory Extraction

**Unit of work:** One conversation transcript (or chunk) → zero or more `memory_write_batch` calls.

**Execution model:** A Claude Code skill (`replay-memory-extraction`) invoked in the current
session. The skill reads the manifest, dispatches one `Agent` subagent per unit (conversation
or chunk), and updates the manifest as each unit completes. Running inside the session means
MCP tools are already wired — no subprocess plumbing or credential passing required.

**Skill location:** `plugins/claude-code/skills/replay-memory-extraction.md`

**Invoke with:** `/replay-memory-extraction` in a Claude Code session (after running Phase 1).

### Subagent prompt template

Each subagent receives:

```
You are extracting memories from a historical Claude Code conversation transcript.
Your job: identify facts that should survive in long-term memory — decisions, preferences,
constraints, personal facts, architectural choices. Write them to agent-brain.

CONTEXT:
- Project: {project}
- Date: {date}
- User identity: nighthawk (abishekkumar92@gmail.com)
- Agent ID to use for all writes: "claude-code-replay"
- Session ID to use: "replay-{uuid8}"

TAXONOMY: Call list_entity_types first to load the current taxonomy.

EXTRACTION RULES:
1. Only write facts that crystallised — a decision made, a preference stated, a constraint
   confirmed. Not observations, not intermediate steps.
2. Each memory must be a single self-contained declarative sentence.
3. Use entity_type + concept per the taxonomy. Map correctly:
   - Facts about nighthawk (the user) → entity_type: "person", concept: "nighthawk"
   - Facts about a project/repo → entity_type: "artifact", concept: "{repo-name}"
   - Facts about a technology → entity_type: "artifact", concept: "{tech-name}"
   - Facts about a design principle/pattern → entity_type: "concept", concept: "{principle-name}"
   - Facts about a place → entity_type: "place", concept: "{place-name}"
4. Confidence:
   - User stated explicitly → 0.90–0.95
   - User confirmed when asked → 0.80–0.85
   - Inferred from multiple consistent signals → 0.70–0.80
   - Skip if below 0.70 or speculative
5. Use memory_write_batch for efficiency (max 20 per call).
6. If a fact feels like a preference or decision that was later reversed in the same
   transcript, write only the final state.
7. Do NOT write: routine code edits, file contents, test output, debugging steps.

TRANSCRIPT:
{transcript_text}

Write all extracted memories now, then respond with a summary: N memories written,
key topics covered.
```

### Large conversation chunking

Some conversations exceed what can be fed to a single subagent in one call. The safe
budget for a transcript (prompt + extraction overhead) is **~40K tokens**. Any conversation
above this threshold must be split into chunks before dispatch.

**Threshold:** conversations with `estimated_tokens > 40000` in the manifest.

Known large conversations from the Phase 1 dry-run:

| Conversation | Tokens | Project |
|---|---|---|
| `superpowers/af2f6fe7` | ~96K | superpowers |
| `infra/f3a5e374` | ~56K | infra |
| `agent-plugins/5b7149d2` | ~55K | agent-plugins |
| `infra/d011780e` | ~52K | infra |
| `agent-brain/29e0cd67` | ~52K | agent-brain |
| `ferrosa/ef779bf1` | ~45K | ferrosa |
| `superclaw/cf4db629` | ~40K | superclaw |

**Splitting strategy:** Divide the transcript into contiguous turn-windows of at most 40K
tokens, with a **10-turn overlap** between adjacent chunks. The overlap preserves enough
context that the extractor can see how a decision at the end of one chunk was confirmed
at the start of the next.

```
chunk_1: turns 0..N   (≤ 40K tokens)
chunk_2: turns N-10..M (≤ 40K tokens, 10-turn overlap with chunk_1)
chunk_3: turns M-10..end
```

Each chunk is dispatched as a separate subagent with a modified prompt header:

```
CHUNK: {n} of {total}  (covers turns {start}–{end})
NOTE: This is a partial transcript. Do not treat silence on a topic as absence —
the topic may appear in another chunk. Only write facts that are fully resolved
within this chunk or are clearly stated as decisions.
```

**Deduplication across chunks:** The contradiction detection system handles facts
written twice from overlapping chunks. Do not attempt manual dedup — write the fact
in each chunk where it appears and let the governance worker consolidate.

**Phase 2 runner responsibility:** The runner script (Phase 2) reads the manifest,
checks `estimated_tokens` against the threshold, auto-splits large transcripts into
chunk files at `~/.claude/replay/chunks/{project}/{date}-{uuid8}-chunk{n}.txt`, and
dispatches one subagent per chunk in order.

### Processing order

Process conversations chronologically (oldest first). This ensures:
- Early exploratory decisions get written at lower confidence
- Later corrections and reversals correctly supersede them via the contradiction detection system

### Batching

Process one conversation (or chunk) at a time. After each unit, update `manifest.json`
with `"processed": true` and the count of memories written. This allows resuming if a
session is interrupted.

**Rate:** The agent-brain server rate-limits writes per user. Process one subagent at a
time (not in parallel) to avoid hitting limits.

---

## Phase 3 — Verification

After all conversations are processed, run the following checks in a single Claude Code session:

1. **Coverage check** — `memory_overview` to see memory_by_type and subjects_by_domain counts. Should show meaningful entries across `person:nighthawk`, major artifact subjects, and concept subjects.

2. **Spot checks** — `memory_search` on 5–6 known topics (e.g. "entity taxonomy", "k8s deployment", "nighthawk identity", "superpowers workflow") to verify memories were written correctly.

3. **Contradiction review** — `list_contradictions` to surface any conflicts detected between replay memories and live memories. Resolve the important ones.

4. **Audit review** — `memory_audit_tail` to confirm write counts are reasonable (not too few, not too many).

5. **Cleanup flag** — If any replay memories are clearly wrong (hallucinated facts, misattributed decisions), they can be identified by `agent_id = "claude-code-replay"` and removed or corrected.

---

## What This Does Not Do

- **Does not re-process subagent conversations** — subagent transcripts are implementation noise (code review, test runs, tool calls). Skip them.
- **Does not extract code** — code already exists in the repos; no need to memorize implementation details.
- **Does not replace the current live memory system** — replay memories augment it; live writes continue using `entity_type` + `concept` as normal.
- **Does not backfill graph edges** — replay memories written under `claude-code-replay` agent ID will not generate CO_OCCURS edges with each other (different agent + session = no co-occurrence scoring). That's fine — graph edges will build naturally from live usage.

---

## Estimated Effort

| Phase | Time | Cost |
|---|---|---|
| Write extraction script (Phase 1) | ~1 session | $0 |
| Run extraction script | <1 min | $0 |
| Write Phase 2 skill | ~1 session | $0 |
| Process 48 conversations + ~10 extra chunks for large ones | 2–3 sessions | ~$8–20 API |
| Verification | ~30 min | <$1 |

**Token budget breakdown:** 48 conversations totalling ~796K transcript tokens. After
chunking the 7 large conversations, the actual dispatch count is ~58 subagent calls.
At ~$0.15–0.30 per call (Sonnet 4.5, ~15K tokens in + ~2K out per call on average),
total cost is roughly $10–18.
