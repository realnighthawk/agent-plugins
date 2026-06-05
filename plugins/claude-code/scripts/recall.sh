#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/format-recall.sh
source "${SCRIPT_DIR}/lib/format-recall.sh"

input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // empty' | head -c 4000)
if [[ -z "$prompt" ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit"}}'
  exit 0
fi

sid=$(echo "$input" | jq -r '.session_id // empty')
[[ -n "$sid" ]] && export NIGHTHAWK_SESSION_ID="agent-brain-${sid}"

agent_brain_save_last_prompt "$prompt"

query=$(printf '%s' "$prompt" | tr '\n' ' ' | head -c 500)

subjects_file="/tmp/agent-brain-subjects-${NIGHTHAWK_SESSION_ID:-default}"
if [[ -f "$subjects_file" && -s "$subjects_file" ]]; then
  exclude=$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$subjects_file")
  args=$(jq -nc --arg q "$query" --argjson lim "${NIGHTHAWK_RECALL_LIMIT:-8}" \
    --argjson excl "$exclude" \
    '{query:$q, limit:$lim, use_graph:true, exclude_subjects:$excl}')
else
  args=$(jq -nc --arg q "$query" --argjson lim "${NIGHTHAWK_RECALL_LIMIT:-8}" \
    '{query:$q, limit:$lim, use_graph:true}')
fi

block=""
if result=$(agent_brain_mcp_call memory_search "$args" 2>/dev/null); then
  block=$(agent_brain_format_recall "$result" || true)
fi

if [[ -z "$block" ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit"}}'
  exit 0
fi

agent_brain_emit_context "UserPromptSubmit" "$block"
exit 0
