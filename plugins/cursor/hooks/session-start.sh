#!/usr/bin/env bash
# sessionStart: assign NIGHTHAWK_SESSION_ID, fetch three-tier skill block.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/session-skill.sh
source "${SCRIPT_DIR}/lib/session-skill.sh"
agent_brain_load_env || true

input=$(cat)
conv=$(echo "$input" | jq -r '.conversation_id // .conversationId // empty')

if [[ -n "$conv" ]]; then
  agent_brain_save_session "cursor-${conv}"
else
  existing="$(agent_brain_load_session || true)"
  if [[ -n "$existing" ]]; then
    export NIGHTHAWK_SESSION_ID="$existing"
  else
    agent_brain_save_session "cursor-$(date +%s)-$$"
  fi
fi

if [[ -z "${NIGHTHAWK_MCP_URL:-}" ]]; then
  echo '{}'
  exit 0
fi

cwd_basename=$(basename "${CURSOR_PROJECT_DIR:-$(pwd)}")

_run_with_timeout() {
  local seconds=$1; shift
  "$@" &
  local pid=$!
  (sleep "$seconds" && kill "$pid" 2>/dev/null) &
  local watchdog=$!
  wait "$pid" 2>/dev/null || true
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
}

tmp_a=$(mktemp)
tmp_u=$(mktemp)
tmp_p=$(mktemp)
trap 'rm -f "${tmp_a:-}" "${tmp_u:-}" "${tmp_p:-}"' EXIT

(_run_with_timeout 8 agent_brain_mcp_call retrieve_skills_for_context \
  "$(jq -nc --arg aid "${NIGHTHAWK_AGENT_ID:-unknown}" --arg q "agent session context" '{agent_id:$aid,query:$q}')" \
  > "$tmp_a" 2>/dev/null) &
(_run_with_timeout 8 agent_brain_mcp_call memory_preference_profile '{}' \
  > "$tmp_u" 2>/dev/null) &
(_run_with_timeout 8 agent_brain_mcp_call memory_search \
  "$(jq -nc --arg q "$cwd_basename" '{query:$q,limit:6,use_graph:true}')" \
  > "$tmp_p" 2>/dev/null) &
wait

agent_brain_collect_subjects "$tmp_a" "$tmp_u" "$tmp_p"
block=$(agent_brain_build_skill_block "$tmp_a" "$tmp_u" "$tmp_p")
rm -f "$tmp_a" "$tmp_u" "$tmp_p"

if [[ -n "$block" ]]; then
  printf '%s' "$block" > "$(agent_brain_skill_block_file)"
fi

echo '{}'
exit 0
