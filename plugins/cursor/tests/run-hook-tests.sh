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
test "$(cat "$CURSOR_PROJECT_DIR/.cursor/state/agent-brain-session-conv-abc-123")" = "cursor-conv-abc-123"

echo "== recall =="
out=$("${ROOT}/hooks/recall.sh" < "${ROOT}/tests/fixtures/recall-prompt.json")
echo "$out" | jq -e '.additional_context | contains("vegetarian")' >/dev/null

echo "== index =="
MARKER="${TMP}/index-called"
export NIGHTHAWK_MOCK_INDEX_MARKER="$MARKER"
rm -f "$MARKER"
"${ROOT}/hooks/index.sh" < "${ROOT}/tests/fixtures/index-turn.json"
test -f "$MARKER"

rm -rf "$TMP"
echo "All hook tests passed."
