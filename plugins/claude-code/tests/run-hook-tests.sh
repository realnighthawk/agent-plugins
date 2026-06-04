#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export NIGHTHAWK_MCP_CALL="${ROOT}/tests/mock-mcp-call.sh"
export NIGHTHAWK_MCP_URL=http://mock
export NIGHTHAWK_AGENT_ID=claude-test
export NIGHTHAWK_API_KEY=test
export NIGHTHAWK_RECALL_MAX=8
export CLAUDE_PLUGIN_ROOT="$ROOT"
export CLAUDE_PLUGIN_DATA="${TMPDIR:-/tmp}/agent-brain-cc-plugin-$$"

mkdir -p "$CLAUDE_PLUGIN_DATA/state"

echo "== SessionStart =="
out=$("${ROOT}/scripts/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
test "$(cat "$CLAUDE_PLUGIN_DATA/state/agent-brain-session")" = "agent-brain-abc123"

echo "== UserPromptSubmit recall =="
out=$("${ROOT}/scripts/recall.sh" < "${ROOT}/tests/fixtures/recall-prompt.json")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("vegetarian")' >/dev/null
test -f "$CLAUDE_PLUGIN_DATA/state/last-user-prompt"

echo "== Stop index =="
MARKER="${CLAUDE_PLUGIN_DATA}/index-called"
export NIGHTHAWK_MOCK_INDEX_MARKER="$MARKER"
rm -f "$MARKER"
"${ROOT}/scripts/index.sh" < "${ROOT}/tests/fixtures/stop-turn.json"
test -f "$MARKER"

rm -rf "$CLAUDE_PLUGIN_DATA"
echo "All Claude Code hook tests passed."
