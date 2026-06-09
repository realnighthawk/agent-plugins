# Replay Memory Extraction

Extract memories from historical Cursor conversation transcripts into agent-brain.
Reads `~/.cursor/replay/manifest.json`, dispatches one subagent per conversation (or chunk
for large conversations), and updates the manifest as work progresses. Fully resumable —
re-invoking the skill skips already-processed items.

## Pre-requisites

Phase 1 must have been run first:

```bash
python3 ~/.cursor/scripts/extract_conversations.py
```

Or from a local checkout:

```bash
python3 plugins/cursor/scripts/extract_conversations.py
```

This produces `~/.cursor/replay/manifest.json` and the transcript files it references.

---

## Process

### Step 1 — Load manifest

Read `~/.cursor/replay/manifest.json`. Filter to items where `"processed": false`, sorted
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

Write each chunk to `~/.cursor/replay/chunks/{project}/{date}-{uuid8}-chunk{n}of{total}.txt`.

#### 2d. Dispatch extraction subagent for each unit

For each unit, dispatch a subagent with the Task tool using this exact prompt (fill in the placeholders):

---

```
You are extracting memories from a historical Cursor conversation transcript.
Your job: identify facts that should survive in long-term memory and write them to
agent-brain using the MCP tools available to you.

CONTEXT
- Project: {project}
- Date: {date}
- Conversation ID: {uuid}
- Agent ID to use for ALL writes: "cursor-replay"
- Session ID to use: "replay-{uuid8}"
{chunk_header}

STEP 1 — Taxonomy
Call list_entity_types({ agent_id: "cursor-replay" }) to load the current taxonomy.
Do this before writing any memory.

STEP 2 — Classify then Extract

Read the transcript carefully. Before writing anything, classify each extracted item
as a TASK or a FACT. This classification determines the tool you call.

TASKS (write as set_intention — do NOT use memory_write):
- Something that needs to be done: a bug, fix, follow-up, TODO, improvement
- Signals: "requires a fix", "we need to add", "this is broken", "should be updated",
  "next step is", "remind me to", "will do later", any numbered list of action items
- One set_intention per actionable item. Never bundle multiple tasks into one.

FACTS (write as memory_write or memory_write_batch):
- What something IS, how it works, a confirmed state, a preference, a decision

Write all intentions first, then batch the facts.

Apply these rules to facts:

1. Only write conclusions, not observations. "User decided to use pgvector" not
   "User mentioned pgvector".

2. Each memory is one self-contained declarative sentence. If you find yourself
   writing a sentence with "(1)…(2)…" or a semicolon list — stop and split into
   multiple memories or intentions.

3. entity_type describes what the SUBJECT IS — not the domain of the content.
   Ask: "what entity am I writing a fact about?" and use that entity's type.

   - Facts about nighthawk (the user) → entity_type: "person", concept: "nighthawk"
   - Facts about a software tool, repo, or system → entity_type: "artifact", concept: "{repo-slug}"
   - Facts about a technology, library, or framework → entity_type: "concept", concept: "{tech-slug}"
   - Facts about an organization, team, or company → entity_type: "concept", concept: "{org-slug}"
   - Facts about a design principle, pattern, or methodology → entity_type: "concept", concept: "{slug}"
   - Facts about a place → entity_type: "place", concept: "{place-slug}"
   - Facts about a discrete bounded event → entity_type: "event", concept: "{event-slug}"

   WRONG: writing "finance-manager requires two fixes: (1)… (2)…" as inferred_fact,
          entity_type: "artifact", concept: "finance-manager"
   RIGHT: two set_intention calls, one per fix

4. Confidence:
   - User stated it explicitly → 0.90–0.95
   - User confirmed when asked → 0.80–0.85
   - Inferred from multiple consistent signals → 0.70–0.80
   - Skip anything below 0.70

5. If a decision was reversed within this transcript, write only the final state.

6. Use memory_write_batch (max 20 per call) for efficiency on facts.

7. Do NOT write: code edits, file contents, test output, debugging steps, things
   that are obvious from the project codebase itself, task observations (use
   set_intention instead), compound numbered-list content as a single memory.

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

Contradiction detection runs automatically in the background — no manual verification step needed.
If anything looks wrong, memories can be identified by `agent_id = "cursor-replay"` and
corrected or removed on-demand via the memory explorer.

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
