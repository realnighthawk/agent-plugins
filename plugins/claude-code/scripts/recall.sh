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
  # Save triggered intention IDs so index.sh (Stop) can complete them.
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

block=""
[[ -n "$recall_block" ]] && block="$recall_block"
if [[ -n "$intentions_block" ]]; then
  [[ -n "$block" ]] && block+=$'\n\n'
  block+="$intentions_block"
fi

if [[ -z "$block" ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit"}}'
  exit 0
fi

agent_brain_emit_context "UserPromptSubmit" "$block"
exit 0
