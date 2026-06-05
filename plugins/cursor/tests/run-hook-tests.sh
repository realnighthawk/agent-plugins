#!/usr/bin/env bash
# Shell tests for Cursor plugin hooks (mocked MCP).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
export NIGHTHAWK_MCP_CALL="${ROOT}/tests/mock-mcp-call.sh"
export NIGHTHAWK_MCP_URL=http://mock
export NIGHTHAWK_AGENT_ID=cursor-test
export NIGHTHAWK_API_KEY=test
export NIGHTHAWK_RECALL_MAX=8

TMP="${TMPDIR:-/tmp}/agent-brain-hook-test-$$"
export CURSOR_PROJECT_DIR="$TMP"
export HOME="$TMP"
mkdir -p "$CURSOR_PROJECT_DIR/.cursor/state"

echo "== session-start =="
"${ROOT}/hooks/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json"
test "$(cat "$CURSOR_PROJECT_DIR/.cursor/state/agent-brain-session")" = "cursor-conv-abc-123"

echo "== session-start: three tiers injected =="
export NIGHTHAWK_AGENT_ID="cursor-test"
out=$("${ROOT}/hooks/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
echo "$out" | jq -e '. == {}' >/dev/null
sid=$(cat "$CURSOR_PROJECT_DIR/.cursor/state/agent-brain-session")
test -f "/tmp/agent-brain-subjects-${sid}"
test -f "/tmp/agent-brain-skill-block-${sid}"

echo "== session-start: all tiers fail -> clean start =="
rm -f "/tmp/agent-brain-skill-block-$(cat "$CURSOR_PROJECT_DIR/.cursor/state/agent-brain-session")"
FAIL_MOCK=$(mktemp); chmod +x "$FAIL_MOCK"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAIL_MOCK"
REAL_MOCK="${NIGHTHAWK_MCP_CALL}"
export NIGHTHAWK_MCP_CALL="$FAIL_MOCK"
out=$("${ROOT}/hooks/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
echo "$out" | jq -e '. == {}' >/dev/null
test ! -f "/tmp/agent-brain-skill-block-$(cat "$CURSOR_PROJECT_DIR/.cursor/state/agent-brain-session")"
export NIGHTHAWK_MCP_CALL="$REAL_MOCK"
rm -f "$FAIL_MOCK"

echo "== recall =="
out=$("${ROOT}/hooks/recall.sh" < "${ROOT}/tests/fixtures/recall-prompt.json")
echo "$out" | jq -e '.additional_context | contains("vegetarian")' >/dev/null

echo "== recall: injects skill block on first call =="
sid=$(cat "$CURSOR_PROJECT_DIR/.cursor/state/agent-brain-session")
printf '%s' "## Agent context\nagent rules" > "/tmp/agent-brain-skill-block-${sid}"
out=$("${ROOT}/hooks/recall.sh" < "${ROOT}/tests/fixtures/recall-prompt.json")
echo "$out" | jq -e '.additional_context | contains("Agent context")' >/dev/null
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

echo "== index =="
MARKER="${TMP}/index-called"
export NIGHTHAWK_MOCK_INDEX_MARKER="$MARKER"
rm -f "$MARKER"
"${ROOT}/hooks/index.sh" < "${ROOT}/tests/fixtures/index-turn.json"
test -f "$MARKER"

rm -rf "$TMP"
echo "All hook tests passed."
