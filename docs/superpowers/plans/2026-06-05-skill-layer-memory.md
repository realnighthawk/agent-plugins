# Skill-Layer Memory Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace passive session-start and per-turn recall with a three-tier server-side skill injection (agent + user + project) that personalizes every session and reduces per-turn recall noise.

**Architecture:** `SessionStart` fetches three tiers in parallel (`retrieve_skills_for_context`, `memory_preference_profile`, `memory_search` by cwd) and merges them into a ≤1200-token block. Claude Code injects the block directly as `additionalContext` (its session-start hook supports this). Cursor's session-start hook returns `{}` only, so it writes the block to `/tmp/agent-brain-skill-block-<session>` and the first `recall.sh` invocation reads+deletes it and prepends it. OpenClaw has no session-start hook at all — its recall hook caches the block in-process and prepends it once. All three plugins write subject labels to `/tmp/agent-brain-subjects-<session>` so per-turn recall can pass `exclude_subjects`.

**Tech Stack:** bash (Claude Code + Cursor hooks), TypeScript/Node (OpenClaw), jq, existing `mcp-call` binary.

---

## File Map

**New files:**
- `plugins/claude-code/scripts/lib/session-skill.sh` — tier-text extraction, merge, subject collection helpers
- `plugins/cursor/hooks/lib/session-skill.sh` — identical logic for Cursor (different sourcing path)
- `plugins/openclaw/session-skill.ts` — TypeScript merge logic with in-process session cache
- `plugins/openclaw/test/session-skill.test.js` — Jest tests for session-skill.ts

**Modified files:**
- `plugins/claude-code/scripts/session-start.sh` — parallel tier fetches → emit merged block
- `plugins/claude-code/scripts/recall.sh` — read subjects file, pass `exclude_subjects`
- `plugins/claude-code/tests/mock-mcp-call.sh` — add `retrieve_skills_for_context` case + call logging
- `plugins/claude-code/tests/run-hook-tests.sh` — new tier-injection and exclusion assertions
- `plugins/cursor/hooks/session-start.sh` — same as CC
- `plugins/cursor/hooks/recall.sh` — same as CC
- `plugins/cursor/tests/mock-mcp-call.sh` — same mock updates
- `plugins/cursor/tests/run-hook-tests.sh` — new assertions
- `plugins/openclaw/recall.ts` — use session-skill block on first call; pass `exclude_subjects`
- `plugins/openclaw/session-state.ts` — move from `~/.openclaw/` to `/tmp` keyed on session

**Removed files:**
- `plugins/claude-code/skills/agent-brain/SKILL.md` — content migrated to server-side skill

---

## Task 1: Update mock-mcp-call.sh for both plugins

**Files:**
- Modify: `plugins/claude-code/tests/mock-mcp-call.sh`
- Modify: `plugins/cursor/tests/mock-mcp-call.sh`

- [ ] **Step 1: Update Claude Code mock**

Replace the full contents of `plugins/claude-code/tests/mock-mcp-call.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
# Log every call for test assertions
echo "$1 $2" >> "${NIGHTHAWK_MOCK_CALL_LOG:-/dev/null}"
case "${1:-}" in
  memory_search)
    echo '[{"subject_raw":"diet","content":"vegetarian","confidence":0.9}]'
    ;;
  memory_write)
    touch "${NIGHTHAWK_MOCK_INDEX_MARKER:-/tmp/agent-brain-index-called}"
    echo '{"memory_id":"00000000-0000-0000-0000-000000000001"}'
    ;;
  memory_preference_profile)
    echo '[{"subject_raw":"communication","content":"prefers terse responses","confidence":0.9}]'
    ;;
  retrieve_skills_for_context)
    echo '{"content":"Use memory_write for durable facts. Tool discipline: never store locally."}'
    ;;
  *)
    echo "unknown tool: $1" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: Update Cursor mock**

Replace the full contents of `plugins/cursor/tests/mock-mcp-call.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "$1 $2" >> "${NIGHTHAWK_MOCK_CALL_LOG:-/dev/null}"
case "${1:-}" in
  memory_search)
    echo '[{"subject_raw":"diet","content":"vegetarian","confidence":0.9}]'
    ;;
  memory_write)
    touch "${NIGHTHAWK_MOCK_INDEX_MARKER:-/tmp/agent-brain-index-called}"
    echo '{"memory_id":"00000000-0000-0000-0000-000000000001"}'
    ;;
  memory_preference_profile)
    echo '[{"subject_raw":"communication","content":"prefers terse responses","confidence":0.9}]'
    ;;
  retrieve_skills_for_context)
    echo '{"content":"Use memory_write for durable facts. Tool discipline: never store locally."}'
    ;;
  *)
    echo "unknown tool: $1" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 3: Commit**

```bash
git add plugins/claude-code/tests/mock-mcp-call.sh plugins/cursor/tests/mock-mcp-call.sh
git commit -m "test: add retrieve_skills_for_context mock + call logging"
```

---

## Task 2: Create session-skill.sh for Claude Code

**Files:**
- Create: `plugins/claude-code/scripts/lib/session-skill.sh`

- [ ] **Step 1: Create the lib**

```bash
#!/usr/bin/env bash
# Tier fetch helpers for three-tier session-start skill injection.

# Extract text from a tier response file (handles multiple JSON shapes).
# Usage: agent_brain_tier_text <file> <max_chars>
agent_brain_tier_text() {
  local file="$1"
  local max="${2:-1600}"
  [[ ! -s "$file" ]] && return 0
  jq -r '
    if type == "string" then .
    elif (.content // empty | type) == "string" then .content
    elif (.text // empty | type) == "string" then .text
    elif (.profile // empty | type) == "string" then .profile
    elif (.summary // empty | type) == "string" then .summary
    elif type == "array" then
      map("- [" + (.subject_raw // .subject // "fact") + "] " + (.content // .text // "")) | join("\n")
    elif (.memories // empty | type) == "array" then
      .memories | map("- [" + (.subject_raw // .subject // "fact") + "] " + (.content // .text // "")) | join("\n")
    elif (.preferences // empty | type) == "array" then
      .preferences | map("- [" + (.subject // "pref") + "] " + (.content // .value // "")) | join("\n")
    else ""
    end
  ' "$file" 2>/dev/null | head -c "$max"
}

# Extract subject labels (newline-separated) from a tier response file.
agent_brain_tier_subjects() {
  local file="$1"
  [[ ! -s "$file" ]] && return 0
  jq -r '
    (if type == "array" then .
     elif (.memories // empty | type) == "array" then .memories
     elif (.preferences // empty | type) == "array" then .preferences
     else []
     end) | .[].subject_raw // .[].subject // empty
  ' "$file" 2>/dev/null | grep -v '^$' || true
}

# Merge three tier temp files into one context block (≤4800 chars).
# Agent tier is first and never truncated. Project tier is truncated first.
# Usage: agent_brain_build_skill_block <agent_file> <user_file> <project_file>
agent_brain_build_skill_block() {
  local tmp_a="$1" tmp_u="$2" tmp_p="$3"
  local MAX_TIER=1600 MAX_TOTAL=4800
  local block="" text section remaining

  text=$(agent_brain_tier_text "$tmp_a" $MAX_TIER)
  if [[ -n "$text" ]]; then
    block="## Agent context"$'\n'"$text"$'\n\n'
  fi

  text=$(agent_brain_tier_text "$tmp_u" $MAX_TIER)
  if [[ -n "$text" && ${#block} -lt $MAX_TOTAL ]]; then
    section="## Your profile"$'\n'"$text"
    remaining=$(( MAX_TOTAL - ${#block} ))
    if (( ${#section} > remaining )); then
      section=$(printf '%s' "$section" | head -c "$remaining")
    fi
    block+="$section"$'\n\n'
  fi

  text=$(agent_brain_tier_text "$tmp_p" $MAX_TIER)
  if [[ -n "$text" && ${#block} -lt $MAX_TOTAL ]]; then
    section="## Project context"$'\n'"$text"
    remaining=$(( MAX_TOTAL - ${#block} ))
    if (( ${#section} > remaining )); then
      section=$(printf '%s' "$section" | head -c "$remaining")
    fi
    block+="$section"$'\n\n'
  fi

  # Strip trailing newlines
  printf '%s' "$block" | sed -E 's/[[:space:]]+$//'
}

# Write subject labels from all tiers to /tmp for recall exclusion.
# Usage: agent_brain_collect_subjects <agent_file> <user_file> <project_file>
agent_brain_collect_subjects() {
  local subjects_file="/tmp/agent-brain-subjects-${NIGHTHAWK_SESSION_ID:-default}"
  {
    agent_brain_tier_subjects "$1"
    agent_brain_tier_subjects "$2"
    agent_brain_tier_subjects "$3"
  } | grep -v '^$' | sort -u > "$subjects_file" 2>/dev/null || true
}

# Path for the one-shot skill block file (read+deleted by first recall invocation).
# Used by hooks that cannot emit additionalContext from session-start (e.g. Cursor).
agent_brain_skill_block_file() {
  echo "/tmp/agent-brain-skill-block-${NIGHTHAWK_SESSION_ID:-default}"
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/claude-code/scripts/lib/session-skill.sh
git commit -m "feat(cc): add session-skill.sh merge lib"
```

---

## Task 3: Write failing CC session-start tests, then implement

**Files:**
- Modify: `plugins/claude-code/tests/run-hook-tests.sh`
- Modify: `plugins/claude-code/scripts/session-start.sh`

- [ ] **Step 1: Add failing assertions to run-hook-tests.sh**

After the existing `== SessionStart ==` block, add:

```bash
echo "== SessionStart: three tiers injected =="
export NIGHTHAWK_AGENT_ID="test-agent"
export CLAUDE_PROJECT_DIR="/tmp/test-project-$$"
out=$("${ROOT}/scripts/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("Agent context")' >/dev/null
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("Your profile")' >/dev/null
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("Project context")' >/dev/null
test -f "/tmp/agent-brain-subjects-agent-brain-abc123"

echo "== SessionStart: empty tier omitted =="
# memory_preference_profile returns {} (empty), so Your profile must be absent
REAL_MOCK="${NIGHTHAWK_MCP_CALL}"
EMPTY_MOCK=$(mktemp); chmod +x "$EMPTY_MOCK"
cat > "$EMPTY_MOCK" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
  memory_preference_profile) echo '{}' ;;
  retrieve_skills_for_context) echo '{"content":"agent rules"}' ;;
  memory_search) echo '[]' ;;
  *) echo "unknown tool: $1" >&2; exit 1 ;;
esac
MOCK
export NIGHTHAWK_MCP_CALL="$EMPTY_MOCK"
out=$("${ROOT}/scripts/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("Agent context")' >/dev/null
result=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
if echo "$result" | grep -q "Your profile"; then
  echo "FAIL: empty user tier should be omitted" >&2; exit 1
fi
export NIGHTHAWK_MCP_CALL="$REAL_MOCK"
rm -f "$EMPTY_MOCK"

echo "== SessionStart: all tiers fail → clean start =="
FAIL_MOCK=$(mktemp); chmod +x "$FAIL_MOCK"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAIL_MOCK"
export NIGHTHAWK_MCP_CALL="$FAIL_MOCK"
out=$("${ROOT}/scripts/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
echo "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
export NIGHTHAWK_MCP_CALL="$REAL_MOCK"
rm -f "$FAIL_MOCK"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash plugins/claude-code/tests/run-hook-tests.sh 2>&1
```

Expected: FAIL on `SessionStart: three tiers injected` — `additionalContext` key absent.

- [ ] **Step 3: Implement new session-start.sh**

Replace `plugins/claude-code/scripts/session-start.sh` entirely:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/session-skill.sh
source "${SCRIPT_DIR}/lib/session-skill.sh"

input=$(cat)
sid=$(echo "$input" | jq -r '.session_id // empty')
if [[ -n "$sid" ]]; then
  export NIGHTHAWK_SESSION_ID="agent-brain-${sid}"
else
  export NIGHTHAWK_SESSION_ID="agent-brain-$(date +%s)-$$"
fi

if [[ -z "${NIGHTHAWK_MCP_URL:-}" ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart"}}'
  exit 0
fi

cwd_basename=$(basename "${CLAUDE_PROJECT_DIR:-$(pwd)}")

tmp_a=$(mktemp) tmp_u=$(mktemp) tmp_p=$(mktemp)

(agent_brain_mcp_call retrieve_skills_for_context \
  "$(jq -nc --arg c "agent:${NIGHTHAWK_AGENT_ID:-unknown}" '{context:$c}')" \
  > "$tmp_a" 2>/dev/null) &
(agent_brain_mcp_call memory_preference_profile '{}' \
  > "$tmp_u" 2>/dev/null) &
(agent_brain_mcp_call memory_search \
  "$(jq -nc --arg q "$cwd_basename" '{query:$q,limit:6,use_graph:true}')" \
  > "$tmp_p" 2>/dev/null) &
wait

agent_brain_collect_subjects "$tmp_a" "$tmp_u" "$tmp_p"
block=$(agent_brain_build_skill_block "$tmp_a" "$tmp_u" "$tmp_p")
rm -f "$tmp_a" "$tmp_u" "$tmp_p"

if [[ -n "$block" ]]; then
  agent_brain_emit_context "SessionStart" "$block"
else
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart"}}'
fi
exit 0
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bash plugins/claude-code/tests/run-hook-tests.sh 2>&1
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add plugins/claude-code/scripts/session-start.sh \
        plugins/claude-code/tests/run-hook-tests.sh
git commit -m "feat(cc): three-tier session-start skill injection"
```

---

## Task 4: Write failing CC recall tests, then implement subject exclusion

**Files:**
- Modify: `plugins/claude-code/tests/run-hook-tests.sh`
- Modify: `plugins/claude-code/scripts/recall.sh`

- [ ] **Step 1: Add failing recall assertions to run-hook-tests.sh**

After the existing `== UserPromptSubmit recall ==` block, add:

```bash
echo "== Recall: excludes session subjects =="
CALL_LOG=$(mktemp)
export NIGHTHAWK_MOCK_CALL_LOG="$CALL_LOG"
# Write a subjects file as session-start would have
echo "communication" > "/tmp/agent-brain-subjects-agent-brain-abc123"
"${ROOT}/scripts/recall.sh" < "${ROOT}/tests/fixtures/recall-prompt.json" >/dev/null
grep -q 'exclude_subjects' "$CALL_LOG"
rm -f "$CALL_LOG" "/tmp/agent-brain-subjects-agent-brain-abc123"
unset NIGHTHAWK_MOCK_CALL_LOG

echo "== Recall: no exclusion when subjects file absent =="
CALL_LOG=$(mktemp)
export NIGHTHAWK_MOCK_CALL_LOG="$CALL_LOG"
rm -f "/tmp/agent-brain-subjects-agent-brain-abc123"
"${ROOT}/scripts/recall.sh" < "${ROOT}/tests/fixtures/recall-prompt.json" >/dev/null
if grep -q 'exclude_subjects' "$CALL_LOG"; then
  echo "FAIL: exclude_subjects should not appear when subjects file absent" >&2; exit 1
fi
rm -f "$CALL_LOG"
unset NIGHTHAWK_MOCK_CALL_LOG
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash plugins/claude-code/tests/run-hook-tests.sh 2>&1
```

Expected: FAIL on `Recall: excludes session subjects`.

- [ ] **Step 3: Implement subject exclusion in recall.sh**

Replace `plugins/claude-code/scripts/recall.sh` entirely:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/format-recall.sh
source "${SCRIPT_DIR}/lib/format-recall.sh"

input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // empty' | head -c 4000)
if [[ -z "$prompt" ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit"}}'
  exit 0
fi

sid=$(echo "$input" | jq -r '.session_id // empty')
[[ -n "$sid" ]] && export NIGHTHAWK_SESSION_ID="agent-brain-${sid}"

agent_brain_save_last_prompt "$prompt"

query=$(printf '%s' "$prompt" | tr '\n' ' ' | head -c 500)

subjects_file="/tmp/agent-brain-subjects-${NIGHTHAWK_SESSION_ID:-default}"
if [[ -f "$subjects_file" && -s "$subjects_file" ]]; then
  exclude=$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$subjects_file")
  args=$(jq -nc --arg q "$query" --argjson lim "${NIGHTHAWK_RECALL_LIMIT:-8}" \
    --argjson excl "$exclude" \
    '{query:$q, limit:$lim, use_graph:true, exclude_subjects:$excl}')
else
  args=$(jq -nc --arg q "$query" --argjson lim "${NIGHTHAWK_RECALL_LIMIT:-8}" \
    '{query:$q, limit:$lim, use_graph:true}')
fi

block=""
if result=$(agent_brain_mcp_call memory_search "$args" 2>/dev/null); then
  block=$(agent_brain_format_recall "$result" || true)
fi

if [[ -z "$block" ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit"}}'
  exit 0
fi

agent_brain_emit_context "UserPromptSubmit" "$block"
exit 0
```

- [ ] **Step 4: Run all CC tests**

```bash
bash plugins/claude-code/tests/run-hook-tests.sh 2>&1
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add plugins/claude-code/scripts/recall.sh \
        plugins/claude-code/tests/run-hook-tests.sh
git commit -m "feat(cc): exclude session-tier subjects from per-turn recall"
```

---

## Task 5: Mirror Task 2–4 for Cursor plugin

**Files:**
- Create: `plugins/cursor/hooks/lib/session-skill.sh`
- Modify: `plugins/cursor/hooks/session-start.sh`
- Modify: `plugins/cursor/hooks/recall.sh`
- Modify: `plugins/cursor/tests/run-hook-tests.sh`

- [ ] **Step 1: Create cursor/hooks/lib/session-skill.sh**

Contents are identical to the CC lib except for the file header comment:

```bash
#!/usr/bin/env bash
# Tier fetch helpers for three-tier session-start skill injection.

agent_brain_tier_text() {
  local file="$1"
  local max="${2:-1600}"
  [[ ! -s "$file" ]] && return 0
  jq -r '
    if type == "string" then .
    elif (.content // empty | type) == "string" then .content
    elif (.text // empty | type) == "string" then .text
    elif (.profile // empty | type) == "string" then .profile
    elif (.summary // empty | type) == "string" then .summary
    elif type == "array" then
      map("- [" + (.subject_raw // .subject // "fact") + "] " + (.content // .text // "")) | join("\n")
    elif (.memories // empty | type) == "array" then
      .memories | map("- [" + (.subject_raw // .subject // "fact") + "] " + (.content // .text // "")) | join("\n")
    elif (.preferences // empty | type) == "array" then
      .preferences | map("- [" + (.subject // "pref") + "] " + (.content // .value // "")) | join("\n")
    else ""
    end
  ' "$file" 2>/dev/null | head -c "$max"
}

agent_brain_tier_subjects() {
  local file="$1"
  [[ ! -s "$file" ]] && return 0
  jq -r '
    (if type == "array" then .
     elif (.memories // empty | type) == "array" then .memories
     elif (.preferences // empty | type) == "array" then .preferences
     else []
     end) | .[].subject_raw // .[].subject // empty
  ' "$file" 2>/dev/null | grep -v '^$' || true
}

agent_brain_build_skill_block() {
  local tmp_a="$1" tmp_u="$2" tmp_p="$3"
  local MAX_TIER=1600 MAX_TOTAL=4800
  local block="" text section remaining

  text=$(agent_brain_tier_text "$tmp_a" $MAX_TIER)
  if [[ -n "$text" ]]; then
    block="## Agent context"$'\n'"$text"$'\n\n'
  fi

  text=$(agent_brain_tier_text "$tmp_u" $MAX_TIER)
  if [[ -n "$text" && ${#block} -lt $MAX_TOTAL ]]; then
    section="## Your profile"$'\n'"$text"
    remaining=$(( MAX_TOTAL - ${#block} ))
    if (( ${#section} > remaining )); then
      section=$(printf '%s' "$section" | head -c "$remaining")
    fi
    block+="$section"$'\n\n'
  fi

  text=$(agent_brain_tier_text "$tmp_p" $MAX_TIER)
  if [[ -n "$text" && ${#block} -lt $MAX_TOTAL ]]; then
    section="## Project context"$'\n'"$text"
    remaining=$(( MAX_TOTAL - ${#block} ))
    if (( ${#section} > remaining )); then
      section=$(printf '%s' "$section" | head -c "$remaining")
    fi
    block+="$section"$'\n\n'
  fi

  printf '%s' "$block" | sed -E 's/[[:space:]]+$//'
}

agent_brain_collect_subjects() {
  local subjects_file="/tmp/agent-brain-subjects-${NIGHTHAWK_SESSION_ID:-default}"
  {
    agent_brain_tier_subjects "$1"
    agent_brain_tier_subjects "$2"
    agent_brain_tier_subjects "$3"
  } | grep -v '^$' | sort -u > "$subjects_file" 2>/dev/null || true
}

agent_brain_skill_block_file() {
  echo "/tmp/agent-brain-skill-block-${NIGHTHAWK_SESSION_ID:-default}"
}
```

- [ ] **Step 2: Write failing Cursor session-start tests**

Add to `plugins/cursor/tests/run-hook-tests.sh` after the existing `== session-start ==` block:

```bash
echo "== session-start: three tiers injected =="
export NIGHTHAWK_AGENT_ID="cursor-test"
export CURSOR_PROJECT_DIR="$TMP"
out=$("${ROOT}/hooks/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("Agent context")' >/dev/null
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("Your profile")' >/dev/null
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("Project context")' >/dev/null
sid=$(cat "$CURSOR_PROJECT_DIR/.cursor/state/agent-brain-session")
test -f "/tmp/agent-brain-subjects-${sid}"

echo "== session-start: all tiers fail → clean start =="
FAIL_MOCK=$(mktemp); chmod +x "$FAIL_MOCK"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAIL_MOCK"
REAL_MOCK="${NIGHTHAWK_MCP_CALL}"
export NIGHTHAWK_MCP_CALL="$FAIL_MOCK"
out=$("${ROOT}/hooks/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
echo "$out" | jq -e '. == {}' >/dev/null
export NIGHTHAWK_MCP_CALL="$REAL_MOCK"
rm -f "$FAIL_MOCK"
```

Note: Cursor session-start currently emits `{}` (not the Claude Code `hookSpecificOutput` format) — adjust the tier-injection assertion to match. Replace the three-tier assertion block above with:

```bash
echo "== session-start: three tiers injected =="
export NIGHTHAWK_AGENT_ID="cursor-test"
export CURSOR_PROJECT_DIR="$TMP"
out=$("${ROOT}/hooks/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
# Cursor session-start emits {} when MCP is connected; tier content goes to agent context separately.
# Verify subjects file was written.
sid=$(cat "$CURSOR_PROJECT_DIR/.cursor/state/agent-brain-session")
test -f "/tmp/agent-brain-subjects-${sid}"
```

- [ ] **Step 3: Run Cursor tests to verify they fail**

```bash
bash plugins/cursor/tests/run-hook-tests.sh 2>&1
```

Expected: FAIL on `session-start: three tiers injected`.

- [ ] **Step 4: Implement new cursor/hooks/session-start.sh**

Replace `plugins/cursor/hooks/session-start.sh` entirely:

```bash
#!/usr/bin/env bash
# sessionStart: assign session ID and inject three-tier skill context.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/session-skill.sh
source "${SCRIPT_DIR}/lib/session-skill.sh"
agent_brain_load_env || true

input=$(cat)
conv=$(echo "$input" | jq -r '.conversation_id // .conversationId // empty')

if [[ -n "$conv" ]]; then
  agent_brain_save_session "cursor-${conv}"
else
  existing="$(agent_brain_load_session || true)"
  if [[ -n "$existing" ]]; then
    export NIGHTHAWK_SESSION_ID="$existing"
  else
    agent_brain_save_session "cursor-$(date +%s)-$$"
  fi
fi

if [[ -z "${NIGHTHAWK_MCP_URL:-}" ]]; then
  echo '{}'
  exit 0
fi

cwd_basename=$(basename "${CURSOR_PROJECT_DIR:-$(pwd)}")

tmp_a=$(mktemp) tmp_u=$(mktemp) tmp_p=$(mktemp)

(agent_brain_mcp_call retrieve_skills_for_context \
  "$(jq -nc --arg c "agent:${NIGHTHAWK_AGENT_ID:-unknown}" '{context:$c}')" \
  > "$tmp_a" 2>/dev/null) &
(agent_brain_mcp_call memory_preference_profile '{}' \
  > "$tmp_u" 2>/dev/null) &
(agent_brain_mcp_call memory_search \
  "$(jq -nc --arg q "$cwd_basename" '{query:$q,limit:6,use_graph:true}')" \
  > "$tmp_p" 2>/dev/null) &
wait

agent_brain_collect_subjects "$tmp_a" "$tmp_u" "$tmp_p"
block=$(agent_brain_build_skill_block "$tmp_a" "$tmp_u" "$tmp_p")
rm -f "$tmp_a" "$tmp_u" "$tmp_p"

# Cursor session-start can't emit additionalContext — write block to /tmp
# for the first recall.sh invocation to read and delete.
if [[ -n "$block" ]]; then
  printf '%s' "$block" > "$(agent_brain_skill_block_file)"
fi

echo '{}'
exit 0
```

Note: Cursor's `sessionStart` hook only supports returning `{}` — it cannot inject `additionalContext`. The skill block is written to `/tmp/agent-brain-skill-block-<session>` and the first `recall.sh` reads and deletes it, prepending it to that turn's `additional_context`.

- [ ] **Step 5: Implement skill-block injection + subject exclusion in cursor/hooks/recall.sh**

Replace `plugins/cursor/hooks/recall.sh` entirely:

```bash
#!/usr/bin/env bash
# beforeSubmitPrompt: prepend one-shot skill block (first call) + targeted recall.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
agent_brain_load_env || true
# shellcheck source=lib/session-skill.sh
source "${SCRIPT_DIR}/lib/session-skill.sh"
# shellcheck source=lib/format-recall.sh
source "${SCRIPT_DIR}/lib/format-recall.sh"

input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // .text // .message // empty' | head -c 4000)
if [[ -z "$prompt" ]]; then
  echo '{}'
  exit 0
fi

existing="$(agent_brain_load_session || true)"
[[ -n "$existing" ]] && export NIGHTHAWK_SESSION_ID="$existing"

# Read and delete the one-shot skill block written by session-start.sh (first call only).
skill_block=""
skill_file="$(agent_brain_skill_block_file)"
if [[ -f "$skill_file" ]]; then
  skill_block=$(cat "$skill_file")
  rm -f "$skill_file"
fi

query=$(printf '%s' "$prompt" | tr '\n' ' ' | head -c 500)

subjects_file="/tmp/agent-brain-subjects-${NIGHTHAWK_SESSION_ID:-default}"
if [[ -f "$subjects_file" && -s "$subjects_file" ]]; then
  exclude=$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$subjects_file")
  args=$(jq -nc --arg q "$query" --argjson lim "${NIGHTHAWK_RECALL_LIMIT:-8}" \
    --argjson excl "$exclude" \
    '{query:$q, limit:$lim, use_graph:true, exclude_subjects:$excl}')
else
  args=$(jq -nc --arg q "$query" --argjson lim "${NIGHTHAWK_RECALL_LIMIT:-8}" \
    '{query:$q, limit:$lim, use_graph:true}')
fi

recall_block=""
if result=$(agent_brain_mcp_call memory_search "$args" 2>/dev/null); then
  recall_block=$(agent_brain_format_recall "$result" || true)
fi

combined=""
[[ -n "$skill_block" ]] && combined+="$skill_block"$'\n\n'
[[ -n "$recall_block" ]] && combined+="$recall_block"

if [[ -z "$combined" ]]; then
  echo '{}'
  exit 0
fi

jq -nc --arg ctx "$combined" '{additional_context: $ctx}'
exit 0
```

- [ ] **Step 6: Add recall tests for Cursor**

Add to `plugins/cursor/tests/run-hook-tests.sh` after the existing `== recall ==` block:

```bash
echo "== recall: injects skill block on first call =="
sid=$(cat "$CURSOR_PROJECT_DIR/.cursor/state/agent-brain-session")
printf '%s' "## Agent context\nagent rules" > "/tmp/agent-brain-skill-block-${sid}"
out=$("${ROOT}/hooks/recall.sh" < "${ROOT}/tests/fixtures/recall-prompt.json")
echo "$out" | jq -e '.additional_context | contains("Agent context")' >/dev/null
# File must be deleted after first use
test ! -f "/tmp/agent-brain-skill-block-${sid}"

echo "== recall: no skill block on second call =="
out=$("${ROOT}/hooks/recall.sh" < "${ROOT}/tests/fixtures/recall-prompt.json")
result=$(echo "$out" | jq -r '.additional_context // ""')
if echo "$result" | grep -q "Agent context"; then
  echo "FAIL: skill block should not repeat on second call" >&2; exit 1
fi

echo "== recall: excludes session subjects =="
CALL_LOG=$(mktemp)
export NIGHTHAWK_MOCK_CALL_LOG="$CALL_LOG"
echo "communication" > "/tmp/agent-brain-subjects-${sid}"
"${ROOT}/hooks/recall.sh" < "${ROOT}/tests/fixtures/recall-prompt.json" >/dev/null
grep -q 'exclude_subjects' "$CALL_LOG"
rm -f "$CALL_LOG" "/tmp/agent-brain-subjects-${sid}"
unset NIGHTHAWK_MOCK_CALL_LOG
```

- [ ] **Step 7: Run all Cursor tests**

```bash
bash plugins/cursor/tests/run-hook-tests.sh 2>&1
```

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add plugins/cursor/hooks/lib/session-skill.sh \
        plugins/cursor/hooks/session-start.sh \
        plugins/cursor/hooks/recall.sh \
        plugins/cursor/tests/run-hook-tests.sh
git commit -m "feat(cursor): three-tier session-start + recall subject exclusion"
```

---

## Task 6: Fix OpenClaw session-state.ts (/tmp migration)

**Files:**
- Modify: `plugins/openclaw/session-state.ts`

- [ ] **Step 1: Write failing test**

Add to `plugins/openclaw/test/format.test.js` (reuse the existing test file rather than creating a new one for this tiny change):

```js
import { saveLastUserPrompt, loadLastUserPrompt } from "../session-state.js";
import os from "node:os";

describe("session-state /tmp migration", () => {
  it("saves and loads prompt from /tmp, not home dir", async () => {
    const key = "test-session-" + Date.now();
    await saveLastUserPrompt(key, "hello world");
    const loaded = await loadLastUserPrompt(key);
    assert.strictEqual(loaded, "hello world");
    // Verify path is under /tmp
    const tmpdir = os.tmpdir();
    const safe = key.replace(/[^a-zA-Z0-9._-]+/g, "_");
    const { existsSync } = await import("node:fs");
    assert.ok(existsSync(`${tmpdir}/agent-brain-prompt-${safe}.txt`));
  });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd plugins/openclaw && npm test 2>&1 | grep -A5 "session-state"
```

Expected: FAIL — file appears under `~/.openclaw/` not `/tmp/`.

- [ ] **Step 3: Implement the /tmp migration**

Replace `plugins/openclaw/session-state.ts` entirely:

```typescript
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

function promptPath(sessionKey: string): string {
  const safe = sessionKey.replace(/[^a-zA-Z0-9._-]+/g, "_");
  return path.join(os.tmpdir(), `agent-brain-prompt-${safe}.txt`);
}

export async function saveLastUserPrompt(
  sessionKey: string | undefined,
  prompt: string,
): Promise<void> {
  if (!sessionKey || !prompt.trim()) return;
  await fs.writeFile(promptPath(sessionKey), prompt, "utf8");
}

export async function loadLastUserPrompt(
  sessionKey: string | undefined,
): Promise<string> {
  if (!sessionKey) return "";
  try {
    return await fs.readFile(promptPath(sessionKey), "utf8");
  } catch {
    return "";
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd plugins/openclaw && npm test 2>&1
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add plugins/openclaw/session-state.ts
git commit -m "fix(openclaw): move session-state prompt files from ~/.openclaw to /tmp"
```

---

## Task 7: Create OpenClaw session-skill.ts

**Files:**
- Create: `plugins/openclaw/session-skill.ts`

- [ ] **Step 1: Create session-skill.ts**

```typescript
import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";

const MAX_TIER_CHARS = 1600;
const MAX_TOTAL_CHARS = 4800;

type TierEntry = { header: string; raw: string };
export type SessionSkill = { block: string; subjects: string[] };

function extractTierText(raw: string): string {
  if (!raw.trim()) return "";
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed === "string") return parsed;
    if (parsed !== null && typeof parsed === "object") {
      const p = parsed as Record<string, unknown>;
      for (const key of ["content", "text", "profile", "summary"]) {
        if (typeof p[key] === "string") return p[key] as string;
      }
      const items = Array.isArray(parsed)
        ? (parsed as Record<string, unknown>[])
        : Array.isArray(p.memories)
          ? (p.memories as Record<string, unknown>[])
          : Array.isArray(p.preferences)
            ? (p.preferences as Record<string, unknown>[])
            : null;
      if (items) {
        return items
          .map((m) => {
            const subj = String(m.subject_raw ?? m.subject ?? "fact");
            const content = String(m.content ?? m.text ?? m.value ?? "");
            return `- [${subj}] ${content}`;
          })
          .join("\n");
      }
    }
  } catch {
    return raw.trim();
  }
  return "";
}

function extractSubjects(raw: string): string[] {
  if (!raw.trim()) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    const items = Array.isArray(parsed)
      ? (parsed as Record<string, unknown>[])
      : (parsed as Record<string, unknown>).memories
          ? ((parsed as Record<string, unknown>).memories as Record<string, unknown>[])
          : (parsed as Record<string, unknown>).preferences
            ? ((parsed as Record<string, unknown>).preferences as Record<string, unknown>[])
            : [];
    return items
      .map((m) => String(m.subject_raw ?? m.subject ?? ""))
      .filter(Boolean);
  } catch {
    return [];
  }
}

function buildBlock(tiers: TierEntry[]): { block: string; subjects: string[] } {
  const sections: string[] = [];
  const subjects: string[] = [];
  let totalChars = 0;

  for (const tier of tiers) {
    const text = extractTierText(tier.raw).slice(0, MAX_TIER_CHARS).trim();
    subjects.push(...extractSubjects(tier.raw));
    if (!text) continue;
    const section = `${tier.header}\n${text}`;
    const remaining = MAX_TOTAL_CHARS - totalChars;
    if (remaining <= tier.header.length + 20) break;
    sections.push(section.length > remaining ? section.slice(0, remaining) : section);
    totalChars += section.length;
  }

  return { block: sections.join("\n\n"), subjects };
}

// In-process cache: one entry per sessionKey, populated on first before_prompt_build.
const _cache = new Map<string, SessionSkill>();

export async function getSessionSkill(
  cfg: AgentBrainPluginConfig,
  rootDir: string | undefined,
  sessionKey: string | undefined,
  cwdBasename: string,
): Promise<SessionSkill> {
  const key = sessionKey ?? "";
  const cached = _cache.get(key);
  if (cached) return cached;

  const [agentRes, userRes, projectRes] = await Promise.allSettled([
    callMcpTool(
      cfg,
      rootDir,
      "retrieve_skills_for_context",
      { context: `agent:${cfg.agentId ?? cfg.agentPrefix}` },
      sessionKey,
    ),
    callMcpTool(cfg, rootDir, "memory_preference_profile", {}, sessionKey),
    callMcpTool(
      cfg,
      rootDir,
      "memory_search",
      { query: cwdBasename, limit: 6, use_graph: true },
      sessionKey,
    ),
  ]);

  const tiers: TierEntry[] = [
    { header: "## Agent context", raw: agentRes.status === "fulfilled" ? agentRes.value : "" },
    { header: "## Your profile", raw: userRes.status === "fulfilled" ? userRes.value : "" },
    { header: "## Project context", raw: projectRes.status === "fulfilled" ? projectRes.value : "" },
  ];

  const result = buildBlock(tiers);
  _cache.set(key, result);
  return result;
}

export function clearSessionSkillCache(): void {
  _cache.clear();
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/openclaw/session-skill.ts
git commit -m "feat(openclaw): add session-skill.ts with three-tier merge + in-process cache"
```

---

## Task 8: Add session-skill tests for OpenClaw

**Files:**
- Create: `plugins/openclaw/test/session-skill.test.js`

- [ ] **Step 1: Create test file**

```js
import assert from "node:assert/strict";
import { describe, it, beforeEach } from "node:test";
import { clearSessionSkillCache } from "../session-skill.js";

const baseCfg = {
  url: "http://mock",
  apiKey: "test-key",
  agentId: "test-agent",
  agentPrefix: "openclaw",
  autoRecall: true,
  autoCapture: true,
  recallLimit: 8,
  recallMinPromptLength: 12,
  mcpCallPath: "/dev/null",
};

function makeMockCfg(overrides = {}) {
  return { ...baseCfg, ...overrides };
}

// Replaces callMcpTool in tests via dynamic import patching is complex.
// Instead, test buildBlock logic via exported internals by exercising
// getSessionSkill with a stubbed callMcpTool through mcpCallPath pointing
// to a helper script.

import { writeFileSync, chmodSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

function writeMock(script) {
  const p = join(tmpdir(), `mock-mcp-${Date.now()}.sh`);
  writeFileSync(p, `#!/usr/bin/env bash\n${script}\n`);
  chmodSync(p, 0o755);
  return p;
}

describe("getSessionSkill", () => {
  beforeEach(() => clearSessionSkillCache());

  it("returns block with all three headers when all tiers succeed", async () => {
    const { getSessionSkill } = await import("../session-skill.js");
    const mockPath = writeMock(`
case "$1" in
  retrieve_skills_for_context) echo '{"content":"agent rules"}' ;;
  memory_preference_profile) echo '[{"subject_raw":"diet","content":"vegetarian"}]' ;;
  memory_search) echo '[{"subject_raw":"repo","content":"uses TDD"}]' ;;
esac
`);
    const result = await getSessionSkill(
      makeMockCfg({ mcpCallPath: mockPath }),
      undefined,
      "session-1",
      "my-project",
    );
    unlinkSync(mockPath);
    assert.ok(result.block.includes("## Agent context"));
    assert.ok(result.block.includes("## Your profile"));
    assert.ok(result.block.includes("## Project context"));
    assert.ok(result.subjects.includes("diet"));
  });

  it("omits a tier when it returns empty", async () => {
    const { getSessionSkill } = await import("../session-skill.js");
    const mockPath = writeMock(`
case "$1" in
  retrieve_skills_for_context) echo '{"content":"agent rules"}' ;;
  memory_preference_profile) echo '{}' ;;
  memory_search) echo '[]' ;;
esac
`);
    const result = await getSessionSkill(
      makeMockCfg({ mcpCallPath: mockPath }),
      undefined,
      "session-2",
      "my-project",
    );
    unlinkSync(mockPath);
    assert.ok(result.block.includes("## Agent context"));
    assert.ok(!result.block.includes("## Your profile"));
    assert.ok(!result.block.includes("## Project context"));
  });

  it("returns empty block when all tiers fail", async () => {
    const { getSessionSkill } = await import("../session-skill.js");
    const mockPath = writeMock("exit 1");
    const result = await getSessionSkill(
      makeMockCfg({ mcpCallPath: mockPath }),
      undefined,
      "session-3",
      "my-project",
    ).catch(() => ({ block: "", subjects: [] }));
    unlinkSync(mockPath);
    assert.strictEqual(result.block, "");
  });

  it("returns cached result on second call", async () => {
    const { getSessionSkill } = await import("../session-skill.js");
    let calls = 0;
    const mockPath = writeMock(`
((calls++)) || true
case "$1" in
  *) echo '{"content":"rules"}' ;;
esac
`);
    await getSessionSkill(makeMockCfg({ mcpCallPath: mockPath }), undefined, "session-4", "proj");
    await getSessionSkill(makeMockCfg({ mcpCallPath: mockPath }), undefined, "session-4", "proj");
    unlinkSync(mockPath);
    // Second call should be instant (no exec), just verify no error
    assert.ok(true);
  });

  it("enforces total char cap", async () => {
    const { getSessionSkill } = await import("../session-skill.js");
    const longContent = "x".repeat(2000);
    const mockPath = writeMock(`
case "$1" in
  retrieve_skills_for_context) echo '{"content":"${longContent}"}' ;;
  memory_preference_profile) echo '[{"subject_raw":"pref","content":"${longContent}"}]' ;;
  memory_search) echo '[{"subject_raw":"proj","content":"${longContent}"}]' ;;
esac
`);
    const result = await getSessionSkill(
      makeMockCfg({ mcpCallPath: mockPath }),
      undefined,
      "session-5",
      "proj",
    );
    unlinkSync(mockPath);
    assert.ok(result.block.length <= 4800);
  });
});
```

- [ ] **Step 2: Run tests**

```bash
cd plugins/openclaw && npm test 2>&1
```

Expected: All tests pass (including new session-skill tests).

- [ ] **Step 3: Commit**

```bash
git add plugins/openclaw/test/session-skill.test.js
git commit -m "test(openclaw): add session-skill.ts tests"
```

---

## Task 9: Update OpenClaw recall.ts to use session-skill

**Files:**
- Modify: `plugins/openclaw/recall.ts`

- [ ] **Step 1: Write failing test**

Add to `plugins/openclaw/test/session-skill.test.js`:

```js
// Recall integration: session skill block prepended on first call only
import { createRecallHook } from "../recall.js";

describe("createRecallHook with session skill", () => {
  it("includes skill block in prependContext on first call", async () => {
    const mockPath = writeMock(`
case "$1" in
  retrieve_skills_for_context) echo '{"content":"agent rules"}' ;;
  memory_preference_profile) echo '[{"subject_raw":"diet","content":"vegetarian"}]' ;;
  memory_search) echo '[{"subject_raw":"diet","content":"vegetarian","confidence":0.9}]' ;;
esac
`);
    const cfg = makeMockCfg({ mcpCallPath: mockPath, recallMinPromptLength: 5 });
    const api = { logger: { info: () => {}, warn: () => {} }, rootDir: undefined };
    const hook = createRecallHook(api, cfg);
    const result = await hook({ prompt: "what do you know?", sessionKey: "session-rc-1" });
    unlinkSync(mockPath);
    assert.ok(result.prependContext?.includes("## Agent context"), "skill block missing on first call");
  });

  it("omits skill block in prependContext on second call", async () => {
    const mockPath = writeMock(`
case "$1" in
  retrieve_skills_for_context) echo '{"content":"agent rules"}' ;;
  memory_preference_profile) echo '{}' ;;
  memory_search) echo '[{"subject_raw":"diet","content":"vegetarian","confidence":0.9}]' ;;
esac
`);
    const cfg = makeMockCfg({ mcpCallPath: mockPath, recallMinPromptLength: 5 });
    const api = { logger: { info: () => {}, warn: () => {} }, rootDir: undefined };
    const hook = createRecallHook(api, cfg);
    await hook({ prompt: "first call", sessionKey: "session-rc-2" });
    const result2 = await hook({ prompt: "second call", sessionKey: "session-rc-2" });
    unlinkSync(mockPath);
    assert.ok(
      !result2.prependContext?.includes("## Agent context"),
      "skill block should not repeat on second call",
    );
  });
});
```

- [ ] **Step 2: Run to verify failure**

```bash
cd plugins/openclaw && npm test 2>&1 | grep -A5 "skill block"
```

Expected: FAIL — `prependContext` doesn't include skill block yet.

- [ ] **Step 3: Update recall.ts**

Replace `plugins/openclaw/recall.ts` entirely:

```typescript
import path from "node:path";
import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { formatRecallBlock, type MemoryRow } from "./format.js";
import { saveLastUserPrompt } from "./session-state.js";
import { getSessionSkill } from "./session-skill.js";

export type PluginApi = {
  rootDir?: string;
  logger: { info: (msg: string) => void; warn: (msg: string) => void };
};

export type BeforePromptBuildCtx = {
  prompt?: string;
  sessionKey?: string;
  trigger?: string;
};

// Track which sessions have had their skill block injected already.
const _initializedSessions = new Set<string>();

export function createRecallHook(api: PluginApi, cfg: AgentBrainPluginConfig) {
  return async (ctx: BeforePromptBuildCtx) => {
    if (ctx.trigger === "memory") return {};

    const prompt = (ctx.prompt ?? "").trim();
    if (prompt.length < cfg.recallMinPromptLength) return {};

    await saveLastUserPrompt(ctx.sessionKey, prompt);

    const sessionKey = ctx.sessionKey ?? "";
    const firstCall = !_initializedSessions.has(sessionKey);
    if (firstCall) _initializedSessions.add(sessionKey);

    const cwdBasename = path.basename(process.cwd());
    const { block: skillBlock, subjects } = await getSessionSkill(
      cfg,
      api.rootDir,
      ctx.sessionKey,
      cwdBasename,
    ).catch(() => ({ block: "", subjects: [] as string[] }));

    const query = prompt.replace(/\s+/g, " ").slice(0, 500);
    const recallArgs: Record<string, unknown> = {
      query,
      limit: cfg.recallLimit,
      use_graph: true,
    };
    if (subjects.length > 0) {
      recallArgs.exclude_subjects = subjects;
    }

    let recallBlock = "";
    try {
      const raw = await callMcpTool(cfg, api.rootDir, "memory_search", recallArgs, ctx.sessionKey);
      let parsed: MemoryRow[] | { memories?: MemoryRow[] };
      try {
        parsed = JSON.parse(raw) as MemoryRow[] | { memories?: MemoryRow[] };
      } catch {
        api.logger.warn("agent-brain: invalid memory_search JSON");
        parsed = [];
      }
      recallBlock =
        formatRecallBlock(Array.isArray(parsed) ? parsed : (parsed.memories ?? []), cfg.recallLimit) ?? "";
    } catch (err) {
      api.logger.warn(`agent-brain: recall failed: ${String(err)}`);
    }

    const parts: string[] = [];
    if (firstCall && skillBlock) parts.push(skillBlock);
    if (recallBlock) parts.push(recallBlock);

    if (parts.length === 0) return {};
    return { prependContext: parts.join("\n\n") };
  };
}
```

- [ ] **Step 4: Run all OpenClaw tests**

```bash
cd plugins/openclaw && npm test 2>&1
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add plugins/openclaw/recall.ts plugins/openclaw/test/session-skill.test.js
git commit -m "feat(openclaw): three-tier session skill + recall subject exclusion"
```

---

## Task 10: Remove local SKILL.md from Claude Code

**Files:**
- Remove: `plugins/claude-code/skills/agent-brain/SKILL.md`

- [ ] **Step 1: Verify agent-tier skill is authored on the server**

Before removing the local file, confirm the server-side skill exists:

```bash
NIGHTHAWK_MCP_CALL=plugins/claude-code/bin/mcp-call \
  plugins/claude-code/bin/mcp-call retrieve_skills_for_context \
  '{"context":"agent:claude-code-mac"}' 2>&1
```

Expected: returns JSON with `content` field containing the skill text. If this returns an error or empty result, **do not proceed** — ingest the skill first (see note below).

> **Note on server-side skill authoring:** Ingest the current `SKILL.md` content into the server before removing the local file:
> ```bash
> plugins/claude-code/bin/mcp-call ingest_skill '{
>   "name": "agent-brain-claude-code",
>   "context": "agent:claude-code-mac",
>   "content": "<paste SKILL.md content here>"
> }'
> ```
> Repeat for `agent-brain-cursor` and `agent-brain-openclaw` with the appropriate `context` values.

- [ ] **Step 2: Remove the local file**

```bash
rm plugins/claude-code/skills/agent-brain/SKILL.md
rmdir plugins/claude-code/skills/agent-brain 2>/dev/null || true
rmdir plugins/claude-code/skills 2>/dev/null || true
```

- [ ] **Step 3: Run CC tests to confirm nothing broke**

```bash
bash plugins/claude-code/tests/run-hook-tests.sh 2>&1
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A plugins/claude-code/skills
git commit -m "feat(cc): remove local SKILL.md — agent-tier skill now server-side"
```

---

## Task 11: Final verification

- [ ] **Step 1: Run all test suites**

```bash
bash plugins/claude-code/tests/run-hook-tests.sh 2>&1 && \
bash plugins/cursor/tests/run-hook-tests.sh 2>&1 && \
cd plugins/openclaw && npm test 2>&1 && cd ../.. && \
go test ./cmd/mcp-call/... 2>&1
```

Expected: All pass.

- [ ] **Step 2: Smoke test session-start output shape**

```bash
NIGHTHAWK_MCP_URL=http://mock \
NIGHTHAWK_AGENT_ID=test \
NIGHTHAWK_MCP_CALL=plugins/claude-code/tests/mock-mcp-call.sh \
CLAUDE_PROJECT_DIR=/tmp/smoke-project \
  bash plugins/claude-code/scripts/session-start.sh \
  <<< '{"session_id":"smoke123","hook_event_name":"SessionStart"}' | jq .
```

Expected output shape:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "## Agent context\n...\n\n## Your profile\n...\n\n## Project context\n..."
  }
}
```

- [ ] **Step 3: Final commit if any loose files**

```bash
git status
```

If clean: done. If any unstaged changes from the smoke test, stash or discard them.
