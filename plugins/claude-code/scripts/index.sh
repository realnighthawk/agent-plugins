#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/index-heuristic.sh
source "${SCRIPT_DIR}/lib/index-heuristic.sh"

input=$(cat)
assistant=$(echo "$input" | jq -r '.last_assistant_message // empty' | head -c 8000)
sid=$(echo "$input" | jq -r '.session_id // empty')
[[ -n "$sid" ]] && export NIGHTHAWK_SESSION_ID="agent-brain-${sid}"
user="$(agent_brain_load_last_prompt || true)"
rm -f "$(agent_brain_last_prompt_file)" 2>/dev/null || true

# Complete intentions that were triggered (and presumably acted on) during this session.
# IDs are written by recall.sh whenever check_intentions returns triggered status.
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

candidates=$(agent_brain_index_candidates "$user" "$assistant")
count=$(echo "$candidates" | jq 'length')
if [[ "$count" -eq 0 ]]; then
  echo '{}'
  exit 0
fi

echo "$candidates" | jq -c '.[]' | while read -r row; do
  action=$(echo "$row" | jq -r '.action // "memory_write"')
  case "$action" in
    set_intention)
      args=$(echo "$row" | jq -c \
        --arg aid "${NIGHTHAWK_AGENT_ID:-}" \
        '{agent_id:$aid, content:.content, topic:(.topic // "")}')
      agent_brain_mcp_call set_intention "$args" >/dev/null 2>&1 || true
      ;;
    *)
      args=$(echo "$row" | jq -c \
        --arg agent "${NIGHTHAWK_AGENT_ID:-}" \
        --arg session "${NIGHTHAWK_SESSION_ID:-}" \
        '. + {agent_id:$agent, session_id:$session}')
      agent_brain_mcp_call memory_write "$args" >/dev/null 2>&1 || true
      ;;
  esac
done

echo '{}'
exit 0
