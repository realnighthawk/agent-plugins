#!/usr/bin/env bash
# sessionStart: assign NIGHTHAWK_SESSION_ID for this Composer thread.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
agent_brain_load_env || true

input=$(cat)
conv=$(echo "$input" | jq -r '.conversation_id // .conversationId // empty')

if [[ -n "$conv" ]]; then
  mkdir -p "$(agent_brain_state_dir)"
  sid_file="$(agent_brain_state_dir)/agent-brain-session-${conv}"
  if [[ -f "$sid_file" ]]; then
    agent_brain_save_session "$(cat "$sid_file")"
  else
    sid="cursor-${conv}"
    printf '%s' "$sid" > "$sid_file"
    agent_brain_save_session "$sid"
  fi
else
  existing="$(agent_brain_load_session || true)"
  if [[ -n "$existing" ]]; then
    export NIGHTHAWK_SESSION_ID="$existing"
  else
    agent_brain_save_session "cursor-$(date +%s)-$$"
  fi
fi

if [[ -n "${NIGHTHAWK_MCP_URL:-}" ]]; then
  agent_brain_mcp_call memory_preference_profile '{}' >/dev/null 2>&1 || true
fi

echo '{}'
exit 0
