#!/usr/bin/env bash
# beforeSubmitPrompt: memory_search + check_intentions → inject context via additional_context.
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
if skill_block=$(cat "$skill_file" 2>/dev/null); then
  rm -f "$skill_file"
fi

query=$(printf '%s' "$prompt" | tr '\n' ' ' | head -c 500)

subjects_file="/tmp/agent-brain-subjects-${NIGHTHAWK_SESSION_ID:-default}"
if [[ -f "$subjects_file" && -s "$subjects_file" ]]; then
  exclude=$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$subjects_file")
  recall_args=$(jq -nc --arg q "$query" --argjson lim "${NIGHTHAWK_RECALL_LIMIT:-8}" \
    --argjson excl "$exclude" \
    '{query:$q, limit:$lim, use_graph:true, exclude_subjects:$excl}')
else
  recall_args=$(jq -nc --arg q "$query" --argjson lim "${NIGHTHAWK_RECALL_LIMIT:-8}" \
    '{query:$q, limit:$lim, use_graph:true}')
fi

intentions_args=$(jq -nc \
  --arg aid "${NIGHTHAWK_AGENT_ID:-}" \
  --arg ctx "$query" \
  '{agent_id:$aid, context_text:$ctx}')

tmp_r=$(mktemp)
tmp_i=$(mktemp)
trap 'rm -f "${tmp_r:-}" "${tmp_i:-}"' EXIT

(agent_brain_mcp_call memory_search "$recall_args" > "$tmp_r" 2>/dev/null) &
(agent_brain_mcp_call check_intentions "$intentions_args" > "$tmp_i" 2>/dev/null) &
wait

recall_block=""
if [[ -s "$tmp_r" ]]; then
  recall_block=$(agent_brain_format_recall "$(cat "$tmp_r")" || true)
fi

intentions_block=""
if [[ -s "$tmp_i" ]]; then
  # Save triggered intention IDs so afterAgentResponse can complete them.
  triggered_ids=$(jq -r '
    (if type == "array" then . elif .intentions then .intentions else [] end)[]
    | select(.status == "triggered")
    | .id // .ID // empty
  ' "$tmp_i" 2>/dev/null | grep -v '^$' || true)
  if [[ -n "$triggered_ids" ]]; then
    triggered_file="/tmp/agent-brain-triggered-intentions-${NIGHTHAWK_SESSION_ID:-default}"
    printf '%s\n' "$triggered_ids" >> "$triggered_file"
  fi

  intentions_block=$(agent_brain_format_intentions "$(cat "$tmp_i")" || true)
fi

combined=""
[[ -n "$skill_block" ]] && combined+="$skill_block"$'\n\n'
[[ -n "$recall_block" ]] && combined+="$recall_block"
if [[ -n "$intentions_block" ]]; then
  [[ -n "$combined" ]] && combined+=$'\n\n'
  combined+="$intentions_block"
fi

if [[ -z "$combined" ]]; then
  echo '{}'
  exit 0
fi

jq -nc --arg ctx "$combined" '{additional_context: $ctx}'
exit 0
