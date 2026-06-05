#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

input=$(cat)
sid=$(echo "$input" | jq -r '.session_id // empty')

if [[ -n "$sid" ]]; then
  export NIGHTHAWK_SESSION_ID="agent-brain-${sid}"
else
  export NIGHTHAWK_SESSION_ID="agent-brain-$(date +%s)-$$"
fi

if [[ -n "${NIGHTHAWK_MCP_URL:-}" ]]; then
  agent_brain_mcp_call memory_preference_profile '{}' >/dev/null 2>&1 || true
fi

echo '{"hookSpecificOutput":{"hookEventName":"SessionStart"}}'
exit 0
