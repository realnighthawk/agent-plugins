# Replay Memory Extraction

Extract memories from historical Claude Code conversation transcripts into agent-brain.
Runs Phase 1 extraction via `extract_conversations.py`, then reads
`~/.claude/replay/manifest.json`, dispatches one subagent per conversation (or chunk
for large conversations), and updates the manifest as work progresses. Fully resumable —
re-invoking the skill skips already-processed items.

## Invocation

The user names a project to replay:

```
replay agent-brain
replay agent-brain limit 3
replay agent-brain dry run
replay all projects
```

Parse from the user's message:
- **project** (required unless they say "all projects") — e.g. `agent-brain`, `agent-plugins`
- **limit N** — stop after N conversations
- **dry run** — extract only; print what would be replayed; do not dispatch subagents or write memories
- **start from {date}** — skip conversations before this date during replay

---

## Process

### Step 0 — Extract transcripts (Phase 1)

Run the extraction script with the Bash tool **before** loading the manifest.

**Script path** (use the first that exists):
1. `${CLAUDE_PLUGIN_ROOT}/scripts/extract_conversations.py` (installed plugin)
2. `plugins/claude-code/scripts/extract_conversations.py` (local checkout)
3. `scripts/extract_conversations.py` (repo root)

**Command:**

```bash
# Single project (default — user always names a project)
python3 <script> --project {project}

# All projects (only when user explicitly says "all projects")
python3 <script>

# Dry run — preview extraction without writing files
python3 <script> --project {project} --dry-run
```

If the script exits non-zero or prints `error: project not found`, run:

```bash
python3 <script> --list-projects
```

Report the available project names and stop. Do not guess project slugs.

On success, report extraction summary from script stdout (conversations extracted, token estimate).

If dry run, stop after extraction summary — do not proceed to Steps 1–3.

### Step 1 — Load manifest

Read `~/.claude/replay/manifest.json`. When `--project` was used, the manifest contains
only that project's conversations. Filter to items where `"processed": false`, sorted
by `"date"` ascending (chronological). Apply optional `start from {date}` and `limit N`
filters from the user's message.

Count and report:

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
  Project                 : {project}
  Conversations processed : N
  Total memories written  : M
```

Contradiction detection runs automatically in the background — no manual verification step needed.
If anything looks wrong, memories can be identified by `agent_id = "claude-code-replay"` and
corrected or removed on-demand via the memory explorer.

---

## Resuming

Re-invoke with the same project name. Step 0 re-extracts transcripts and preserves
`"processed": true` for conversations already completed in the prior manifest (matched by UUID).
Only pending conversations are replayed.

To re-process a specific conversation, set its `"processed": false` in the manifest and
re-invoke.

## Manual extraction (optional)

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/extract_conversations.py" --project agent-brain
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/extract_conversations.py" --list-projects
```
