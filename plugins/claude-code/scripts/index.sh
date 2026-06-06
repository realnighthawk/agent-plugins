#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

input=$(cat)
sid=$(echo "$input" | jq -r '.session_id // empty')
[[ -n "$sid" ]] && export NIGHTHAWK_SESSION_ID="agent-brain-${sid}"
rm -f "$(agent_brain_last_prompt_file)" 2>/dev/null || true

# Complete intentions that were triggered (and acted on) during this session.
# IDs are written by recall.sh / session-start.sh whenever check_intentions returns triggered status.
triggered_file="/tmp/agent-brain-triggered-intentions-${NIGHTHAWK_SESSION_ID:-default}"
if [[ -f "$triggered_file" && -s "$triggered_file" ]]; then
  while IFS= read -r intention_id; do
    [[ -z "$intention_id" ]] && continue
    args=$(jq -nc \
      --arg aid "${NIGHTHAWK_AGENT_ID:-}" \
      --arg iid "$intention_id" \
      '{agent_id:$aid, intention_id:$iid}')
    agent_brain_mcp_call complete_intention "$args" >/dev/null 2>&1 || true
  done < "$triggered_file"
  rm -f "$triggered_file" 2>/dev/null || true
fi

echo '{}'
exit 0
