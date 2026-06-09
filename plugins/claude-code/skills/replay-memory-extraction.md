# Replay Memory Extraction

Extract memories from historical Claude Code conversation transcripts into agent-brain.
Reads `~/.claude/replay/manifest.json`, dispatches one subagent per conversation (or chunk
for large conversations), and updates the manifest as work progresses. Fully resumable —
re-invoking the skill skips already-processed items.

## Pre-requisites

Phase 1 must have been run first:

```bash
python3 /Users/abishekkumar/Documents/agent-plugins/scripts/extract_conversations.py
```

This produces `~/.claude/replay/manifest.json` and the transcript files it references.

---

## Process

### Step 1 — Load manifest

Read `~/.claude/replay/manifest.json`. Filter to items where `"processed": false`, sorted
by `"date"` ascending (chronological). Count and report:

```
Manifest loaded. N conversations pending, M already processed.
```

If nothing is pending, report done and stop.

### Step 2 — For each pending item (one at a time, never in parallel)

#### 2a. Read the transcript

Read the file at `item.transcript`. Compute the actual character count.

#### 2b. Decide: whole or chunked?

**Threshold: 40,000 estimated tokens** (~160,000 characters).

- **Under threshold** → process as a single unit. Set `units = [{chunk: null, text: transcript_text}]`.
- **Over threshold** → split into chunks (see Chunking below). Set `units = [{chunk: 1, text: ...}, {chunk: 2, text: ...}, ...]`.

#### 2c. Chunking (large conversations only)

Parse the transcript into turns. A turn starts with `USER:` or `A:` at the start of a line.

Build chunks greedily:
- Target: ≤ 160,000 characters per chunk
- Overlap: include the last 10 turns of the previous chunk at the start of the next
- Label each chunk: `chunk N of total`

Write each chunk to `~/.claude/replay/chunks/{project}/{date}-{uuid8}-chunk{n}of{total}.txt`.

#### 2d. Dispatch extraction subagent for each unit

For each unit, dispatch a subagent with this exact prompt (fill in the placeholders):

---

```
You are extracting memories from a historical Claude Code conversation transcript.
Your job: identify facts that should survive in long-term memory and write them to
agent-brain using the MCP tools available to you.

CONTEXT
- Project: {project}
- Date: {date}
- Conversation ID: {uuid}
- User identity: nighthawk (abishekkumar92@gmail.com)
- Agent ID to use for ALL writes: "claude-code-replay"
- Session ID to use: "replay-{uuid8}"
{chunk_header}

STEP 1 — Taxonomy
Call list_entity_types({ agent_id: "claude-code-replay" }) to load the current taxonomy.
Do this before writing any memory.

STEP 2 — Extract

Read the transcript carefully. For every fact that crystallised — a decision made, a
preference stated, a constraint confirmed, a personal fact established — write it as a
memory. Apply these rules:

1. Only write conclusions, not observations. "User decided to use pgvector" not
   "User mentioned pgvector".

2. Each memory is one self-contained declarative sentence.

3. entity_type + concept mapping:
   - Facts about nighthawk (the user) → entity_type: "person", concept: "nighthawk"
   - Facts about a codebase/tool/repo → entity_type: "artifact", concept: "{repo-name}"
   - Facts about a technology or library → entity_type: "artifact", concept: "{tech-name}"
   - Facts about a design principle or pattern → entity_type: "concept", concept: "{slug}"
   - Facts about a place → entity_type: "place", concept: "{place-name}"
   - Facts about an event → entity_type: "event", concept: "{event-slug}"

4. Confidence:
   - User stated it explicitly → 0.90–0.95
   - User confirmed when asked → 0.80–0.85
   - Inferred from multiple consistent signals → 0.70–0.80
   - Skip anything below 0.70

5. If a decision was reversed within this transcript, write only the final state.

6. Use memory_write_batch (max 20 per call) for efficiency.

7. Do NOT write: code edits, file contents, test output, debugging steps, things
   that are obvious from the project codebase itself.

STEP 3 — Report

After all writes, respond with exactly this format so the runner can parse it:

MEMORIES_WRITTEN: {N}
TOPICS: {comma-separated list of subjects written}

TRANSCRIPT
{transcript_or_chunk_text}
```

---

Substitute:
- `{chunk_header}` → empty string for single-unit conversations; for chunks:
  `- Chunk: {n} of {total} (this is a partial transcript — do not treat silence on a topic as absence)`
- `{transcript_or_chunk_text}` → the full transcript or chunk text

#### 2e. Parse result and update manifest

After the subagent returns, parse its response for the line `MEMORIES_WRITTEN: N`.
If not found, default to `"memories_written": 0` and log a warning.

Update `manifest.json`: set `"processed": true`, `"memories_written": N` on the item.

Print progress:
```
✓ {project}/{date}-{uuid8}  →  N memories written  ({topics})
```

### Step 3 — Final summary

After all items are processed:

```
Replay complete.
  Conversations processed : N
  Total memories written  : M
  Projects covered        : [list]
```

Suggest running Phase 3 verification:
- `memory_overview` for coverage
- `memory_search` on "nighthawk", "agent-brain", "superpowers workflow"
- `list_contradictions` for any conflicts between replay and live memories

---

## Resuming

If the skill is interrupted mid-run, re-invoke it. The manifest tracks `"processed": true`
per item, so already-completed conversations are skipped automatically.

To re-process a specific conversation, set its `"processed": false` in the manifest and
re-invoke.

## Flags (pass as natural language when invoking)

- **"dry run"** — print what would be dispatched without calling any subagents or writing memories
- **"only {project}"** — process only conversations from the named project
- **"start from {date}"** — skip conversations before this date
- **"limit N"** — stop after processing N conversations (useful for testing with a small batch first)
