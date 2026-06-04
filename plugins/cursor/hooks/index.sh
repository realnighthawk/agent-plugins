#!/usr/bin/env bash
# afterAgentResponse / stop: conservative memory_write batch.
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

candidates=$(agent_brain_index_candidates "$user" "$assistant")
count=$(echo "$candidates" | jq 'length')
if [[ "$count" -eq 0 ]]; then
  echo '{}'
  exit 0
fi

echo "$candidates" | jq -c '.[]' | while read -r row; do
  args=$(echo "$row" | jq -c \
    --arg agent "${NIGHTHAWK_AGENT_ID:-}" \
    --arg session "${NIGHTHAWK_SESSION_ID:-}" \
    '. + {agent_id: $agent, session_id: $session}')
  agent_brain_mcp_call memory_write "$args" >/dev/null 2>&1 || true
done

echo '{}'
exit 0
