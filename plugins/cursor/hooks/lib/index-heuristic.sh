#!/usr/bin/env bash
# Write candidates from user/assistant turn text — 5 tiers.

agent_brain_index_candidates() {
  local user="$1"
  local _assistant="$2"

  if [[ ${#user} -lt 12 ]]; then
    echo '[]'
    return 0
  fi
  if echo "$user" | grep -qiE '^(ok|thanks|thank you|yes|no|sure|done|got it|sounds good)[.!]?$'; then
    echo '[]'
    return 0
  fi

  local subj

  # Tier 1: explicit stated preferences
  if echo "$user" | grep -qiE '\b(i prefer|i like|i love|i hate|i always|i never|i want|i need|my goal is|i am allergic)\b'; then
    subj=$(echo "$user" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | cut -c1-40)
    jq -nc --arg c "$user" --arg s "$subj" \
      '[{content:$c, signal_type:"user-stated", memory_type:"stated_fact", subject:$s, confidence:0.90}]'
    return 0
  fi

  # Tier 2: corrections
  if echo "$user" | grep -qiE '^\s*(no[,.]?\s+(not that|actually|do|use|try)|actually[,]?\s+|wrong[,.]?\s+|instead[,]?\s+|not\s+\w+[,]?\s+use\b)'; then
    subj="correction-$(echo "$user" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | cut -c1-36)"
    jq -nc --arg c "$user" --arg s "$subj" \
      '[{content:$c, signal_type:"user-stated", memory_type:"stated_fact", subject:$s, confidence:0.85}]'
    return 0
  fi

  # Tier 3: project constraints / conventions
  if echo "$user" | grep -qiE '\b(in this (project|repo|codebase|service)|our convention|we always|we never|we don.t use|we use|we decided|let.s use|going with|use the)\b'; then
    subj="project-convention-$(echo "$user" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | cut -c1-30)"
    jq -nc --arg c "$user" --arg s "$subj" \
      '[{content:$c, signal_type:"user-stated", memory_type:"stated_fact", subject:$s, confidence:0.80}]'
    return 0
  fi

  # Tier 4: architectural decisions confirmed
  if echo "$user" | grep -qiE '\b(let.s go with|we.ll use|decided to|going to use|approach is|architecture is|design is)\b'; then
    subj="decision-$(echo "$user" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | cut -c1-34)"
    jq -nc --arg c "$user" --arg s "$subj" \
      '[{content:$c, signal_type:"inferred", memory_type:"stated_fact", subject:$s, confidence:0.75}]'
    return 0
  fi

  # Tier 5: deferred items → set_intention (safety net; Plane 2 should catch these first)
  if echo "$user" | grep -qiE '\b(remind me|i.ll (do|check|fix|look at|revisit)|follow up on|i should(n.t forget)?|we should|don.t forget|next time|come back to)\b'; then
    local topic
    topic=$(echo "$user" | tr '[:upper:]' '[:lower:]' | \
      grep -oE '(remind me (to )?|follow up on |i.ll |check |fix |look at |revisit |come back to )[a-z0-9 _-]+' | \
      head -1 | sed -E 's/^(remind me (to )?|follow up on |i.ll |check |fix |look at |revisit |come back to )//' | \
      cut -c1-60 || echo "task")
    jq -nc --arg c "$user" --arg t "$topic" \
      '[{action:"set_intention", content:$c, topic:$t}]'
    return 0
  fi

  echo '[]'
}
