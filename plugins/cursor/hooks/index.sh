#!/usr/bin/env bash
# afterAgentResponse / stop: complete intentions, route candidates to memory_write / set_intention.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
agent_brain_load_env || true
# shellcheck source=lib/index-heuristic.sh
source "${SCRIPT_DIR}/lib/index-heuristic.sh"

input=$(cat)
user=$(echo "$input" | jq -r '.user_message // .prompt // empty' | head -c 8000)
assistant=$(echo "$input" | jq -r '.assistant_message // .response // empty' | head -c 8000)

existing="$(agent_brain_load_session || true)"
[[ -n "$existing" ]] && export NIGHTHAWK_SESSION_ID="$existing"

# Phase 1: complete intentions that were triggered during this session.
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

# Phase 2+3: run heuristic and route candidates.
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
        '. + {agent_id: $agent, session_id: $session}')
      agent_brain_mcp_call memory_write "$args" >/dev/null 2>&1 || true
      ;;
  esac
done

echo '{}'
exit 0
