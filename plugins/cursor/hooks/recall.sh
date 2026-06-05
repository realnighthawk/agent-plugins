#!/usr/bin/env bash
# beforeSubmitPrompt: memory_search → inject context via additional_context.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/session-skill.sh
source "${SCRIPT_DIR}/lib/session-skill.sh"
# shellcheck source=lib/format-recall.sh
source "${SCRIPT_DIR}/lib/format-recall.sh"
agent_brain_load_env || true

input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // .text // .message // empty' | head -c 4000)
if [[ -z "$prompt" ]]; then
  echo '{}'
  exit 0
fi

existing="$(agent_brain_load_session || true)"
[[ -n "$existing" ]] && export NIGHTHAWK_SESSION_ID="$existing"

skill_block=""
skill_file="$(agent_brain_skill_block_file)"
if [[ -f "$skill_file" ]]; then
  skill_block=$(cat "$skill_file")
  rm -f "$skill_file"
fi

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

recall_block=""
if result=$(agent_brain_mcp_call memory_search "$args" 2>/dev/null); then
  recall_block=$(agent_brain_format_recall "$result" || true)
fi

combined=""
[[ -n "$skill_block" ]] && combined+="$skill_block"$'\n\n'
[[ -n "$recall_block" ]] && combined+="$recall_block"

if [[ -z "$combined" ]]; then
  echo '{}'
  exit 0
fi

jq -nc --arg ctx "$combined" '{additional_context: $ctx}'
exit 0
