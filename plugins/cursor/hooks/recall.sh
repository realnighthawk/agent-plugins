#!/usr/bin/env bash
# beforeSubmitPrompt: memory_search → inject context via additional_context.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
agent_brain_load_env || true
# shellcheck source=lib/format-recall.sh
source "${SCRIPT_DIR}/lib/format-recall.sh"

input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // .text // .message // empty' | head -c 4000)
if [[ -z "$prompt" ]]; then
  echo '{}'
  exit 0
fi

existing="$(agent_brain_load_session || true)"
[[ -n "$existing" ]] && export NIGHTHAWK_SESSION_ID="$existing"

query=$(printf '%s' "$prompt" | tr '\n' ' ' | head -c 500)
args=$(jq -nc --arg q "$query" --argjson lim "${NIGHTHAWK_RECALL_LIMIT:-8}" \
  '{query:$q, limit:$lim, use_graph:true}')

block=""
if result=$(agent_brain_mcp_call memory_search "$args" 2>/dev/null); then
  block=$(agent_brain_format_recall "$result" || true)
fi

if [[ -z "$block" ]]; then
  echo '{}'
  exit 0
fi

jq -nc --arg ctx "$block" '{additional_context: $ctx}'
exit 0
