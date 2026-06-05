#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export NIGHTHAWK_MCP_CALL="${ROOT}/tests/mock-mcp-call.sh"
export NIGHTHAWK_MCP_URL=http://mock
export NIGHTHAWK_AGENT_ID=claude-test
export NIGHTHAWK_API_KEY=test
export NIGHTHAWK_RECALL_MAX=8
export CLAUDE_PLUGIN_ROOT="$ROOT"
PROMPT_FILE="/tmp/agent-brain-prompt-agent-brain-abc123"
rm -f "$PROMPT_FILE"

echo "== SessionStart =="
"${ROOT}/scripts/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json" >/dev/null

echo "== UserPromptSubmit recall =="
out=$("${ROOT}/scripts/recall.sh" < "${ROOT}/tests/fixtures/recall-prompt.json")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("vegetarian")' >/dev/null
test -f "$PROMPT_FILE"

echo "== Stop index =="
TMP="${TMPDIR:-/tmp}/agent-brain-cc-test-$$"
mkdir -p "$TMP"
MARKER="${TMP}/index-called"
export NIGHTHAWK_MOCK_INDEX_MARKER="$MARKER"
rm -f "$MARKER"
"${ROOT}/scripts/index.sh" < "${ROOT}/tests/fixtures/stop-turn.json"
test -f "$MARKER"
test ! -f "$PROMPT_FILE"

rm -rf "$TMP"
echo "All Claude Code hook tests passed."
