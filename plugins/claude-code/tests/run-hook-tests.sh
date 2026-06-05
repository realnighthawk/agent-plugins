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

echo "== SessionStart: three tiers injected =="
export NIGHTHAWK_AGENT_ID="test-agent"
export CLAUDE_PROJECT_DIR="/tmp/test-project-$$"
out=$("${ROOT}/scripts/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("Agent context")' >/dev/null
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("Your profile")' >/dev/null
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("Project context")' >/dev/null
test -f "/tmp/agent-brain-subjects-agent-brain-abc123"

echo "== SessionStart: empty tier omitted =="
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

echo "== SessionStart: all tiers fail -> clean start =="
FAIL_MOCK=$(mktemp); chmod +x "$FAIL_MOCK"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAIL_MOCK"
export NIGHTHAWK_MCP_CALL="$FAIL_MOCK"
out=$("${ROOT}/scripts/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
echo "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
export NIGHTHAWK_MCP_CALL="$REAL_MOCK"
rm -f "$FAIL_MOCK"

echo "== SessionStart: token cap enforced =="
OVERSIZE_MOCK=$(mktemp); chmod +x "$OVERSIZE_MOCK"
# Generate a mock that returns >1600 chars per tier
cat > "$OVERSIZE_MOCK" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
  retrieve_skills_for_context)
    content=$(printf '%2000s' | tr ' ' 'x')
    echo "[{\"subject_raw\":\"rule\",\"content\":\"$content\"}]" ;;
  memory_preference_profile)
    content=$(printf '%2000s' | tr ' ' 'y')
    echo "[{\"subject_raw\":\"pref\",\"content\":\"$content\"}]" ;;
  memory_search)
    content=$(printf '%2000s' | tr ' ' 'z')
    echo "[{\"subject_raw\":\"proj\",\"content\":\"$content\"}]" ;;
  *) echo "unknown tool: $1" >&2; exit 1 ;;
esac
MOCK
export NIGHTHAWK_MCP_CALL="$OVERSIZE_MOCK"
out=$("${ROOT}/scripts/session-start.sh" < "${ROOT}/tests/fixtures/session-start.json")
result=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
if [[ ${#result} -gt 4800 ]]; then
  echo "FAIL: additionalContext exceeds 4800 chars (got ${#result})" >&2; exit 1
fi
export NIGHTHAWK_MCP_CALL="${ROOT}/tests/mock-mcp-call.sh"
rm -f "$OVERSIZE_MOCK"

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
