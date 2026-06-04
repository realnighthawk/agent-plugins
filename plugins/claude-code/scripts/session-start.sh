#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

input=$(cat)
sid=$(echo "$input" | jq -r '.session_id // empty')

if [[ -n "$sid" ]]; then
  agent_brain_save_session "agent-brain-${sid}"
else
  existing="$(agent_brain_load_session || true)"
  if [[ -n "$existing" ]]; then
    export NIGHTHAWK_SESSION_ID="$existing"
  else
    agent_brain_save_session "agent-brain-$(date +%s)-$$"
  fi
fi

if [[ -n "${NIGHTHAWK_MCP_URL:-}" ]]; then
  agent_brain_mcp_call memory_preference_profile '{}' >/dev/null 2>&1 || true
fi

echo '{"hookSpecificOutput":{"hookEventName":"SessionStart"}}'
exit 0
