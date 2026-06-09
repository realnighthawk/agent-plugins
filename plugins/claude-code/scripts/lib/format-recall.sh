#!/usr/bin/env bash

agent_brain_format_recall() {
  local json="$1"
  local max_items="${NIGHTHAWK_RECALL_MAX:-8}"
  local lines
  lines=$(echo "$json" | jq -r --argjson max "$max_items" '
    (if type == "array" then . elif .memories then .memories else [] end)[:$max][]
    | "- [\(.subject_raw // .SubjectRaw // "fact")] \(.content // .Content) (conf \(.confidence // .Confidence // 0.8))"
  ' 2>/dev/null) || return 1
  if [[ -z "$lines" ]]; then
    return 0
  fi
  printf '%s\n%s' "## Memory context (agent-brain)" "$lines"
}

agent_brain_format_entity_types() {
  local json="$1"
  local lines
  lines=$(echo "$json" | jq -r '
    (if type == "object" and (.types // empty | type) == "array" then .types
     elif type == "array" then .
     else [] end)[]
    | "- \(.name)\(if .is_root then " (root)" else "" end): \(.description // "")"
  ' 2>/dev/null) || return 1
  if [[ -z "$lines" ]]; then
    return 0
  fi
  printf '%s\n%s' "## Entity taxonomy (agent-brain)" "$lines"
}

agent_brain_format_intentions() {
  local json="$1"
  local lines
  lines=$(echo "$json" | jq -r '
    (if type == "array" then . elif .intentions then .intentions else [] end)[]
    | select(.status == "pending" or .status == "triggered")
    | "- [intention: \(.topic // "task")] \(.content)"
  ' 2>/dev/null) || return 1
  if [[ -z "$lines" ]]; then
    return 0
  fi
  printf '%s\n%s' "## Pending intentions" "$lines"
}
