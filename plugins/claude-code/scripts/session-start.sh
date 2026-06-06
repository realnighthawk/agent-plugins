#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/session-skill.sh
source "${SCRIPT_DIR}/lib/session-skill.sh"
# shellcheck source=lib/format-recall.sh
source "${SCRIPT_DIR}/lib/format-recall.sh"

input=$(cat)
sid=$(echo "$input" | jq -r '.session_id // empty')
if [[ -n "$sid" ]]; then
  export NIGHTHAWK_SESSION_ID="agent-brain-${sid}"
else
  export NIGHTHAWK_SESSION_ID="agent-brain-$(date +%s)-$$"
fi

if [[ -z "${NIGHTHAWK_MCP_URL:-}" ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart"}}'
  exit 0
fi

cwd_basename=$(basename "${CLAUDE_PROJECT_DIR:-$(pwd)}")

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
tmp_int=$(mktemp)
trap 'rm -f "${tmp_a:-}" "${tmp_u:-}" "${tmp_p:-}" "${tmp_int:-}"' EXIT

(_run_with_timeout 8 agent_brain_mcp_call retrieve_skills_for_context \
  "$(jq -nc --arg aid "${NIGHTHAWK_AGENT_ID:-unknown}" --arg q "agent session context" '{agent_id:$aid,query:$q}')" \
  > "$tmp_a" 2>/dev/null) &
(_run_with_timeout 8 agent_brain_mcp_call memory_preference_profile '{}' \
  > "$tmp_u" 2>/dev/null) &
(_run_with_timeout 8 agent_brain_mcp_call memory_search \
  "$(jq -nc --arg q "$cwd_basename" '{query:$q,limit:6,use_graph:true}')" \
  > "$tmp_p" 2>/dev/null) &
(_run_with_timeout 8 agent_brain_mcp_call check_intentions \
  "$(jq -nc --arg aid "${NIGHTHAWK_AGENT_ID:-unknown}" --arg ctx "session start ${cwd_basename}" \
    '{agent_id:$aid,context_text:$ctx}')" \
  > "$tmp_int" 2>/dev/null) &
wait

agent_brain_collect_subjects "$tmp_a" "$tmp_u" "$tmp_p"
block=$(agent_brain_build_skill_block "$tmp_a" "$tmp_u" "$tmp_p")

# Append past-due / topic-matched intentions as a separate section.
if [[ -s "$tmp_int" ]]; then
  intentions_block=$(agent_brain_format_intentions "$(cat "$tmp_int")" || true)
  if [[ -n "$intentions_block" ]]; then
    [[ -n "$block" ]] && block+=$'\n\n'
    block+="$intentions_block"
  fi

  # Save triggered IDs so Stop hook can complete them.
  triggered_ids=$(jq -r '
    (if type == "array" then . elif .intentions then .intentions else [] end)[]
    | select(.status == "triggered")
    | .id // .ID // empty
  ' "$tmp_int" 2>/dev/null | grep -v '^$' || true)
  if [[ -n "$triggered_ids" ]]; then
    triggered_file="/tmp/agent-brain-triggered-intentions-${NIGHTHAWK_SESSION_ID}"
    printf '%s\n' "$triggered_ids" >> "$triggered_file"
  fi
fi

rm -f "$tmp_a" "$tmp_u" "$tmp_p" "$tmp_int"

if [[ -n "$block" ]]; then
  agent_brain_emit_context "SessionStart" "$block"
else
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart"}}'
fi
exit 0
