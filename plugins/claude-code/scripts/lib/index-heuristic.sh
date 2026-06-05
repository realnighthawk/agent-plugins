#!/usr/bin/env bash

agent_brain_index_candidates() {
  local user="$1"
  local _assistant="$2"

  if [[ ${#user} -lt 12 ]]; then
    echo '[]'
    return 0
  fi
  if echo "$user" | grep -qiE '^(ok|thanks|thank you|yes|no|sure|done)[.!]?$'; then
    echo '[]'
    return 0
  fi

  if echo "$user" | grep -qiE '\b(i prefer|i like|i love|i hate|i always|i never|my goal is|i am allergic)\b'; then
    local subj
    subj=$(echo "$user" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | cut -c1-40)
    jq -nc --arg c "$user" --arg s "$subj" \
      '[{content:$c, signal_type:"user-stated", memory_type:"stated_fact", subject:$s, confidence:0.85}]'
    return 0
  fi

  echo '[]'
}
