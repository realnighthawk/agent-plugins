#!/usr/bin/env bash
# Tier fetch helpers for three-tier session-start skill injection.

# Extract text from a tier response file (handles multiple JSON shapes).
# Usage: agent_brain_tier_text <file> <max_chars>
agent_brain_tier_text() {
  local file="$1"
  local max="${2:-1600}"
  [[ ! -s "$file" ]] && return 0
  jq -r '
    if type == "string" then .
    elif (.content // empty | type) == "string" then .content
    elif (.text // empty | type) == "string" then .text
    elif (.profile // empty | type) == "string" then .profile
    elif (.summary // empty | type) == "string" then .summary
    elif type == "array" then
      map("- [" + (.subject_raw // .subject // "fact") + "] " + (.content // .text // "")) | join("\n")
    elif (.memories // empty | type) == "array" then
      .memories | map("- [" + (.subject_raw // .subject // "fact") + "] " + (.content // .text // "")) | join("\n")
    elif (.preferences // empty | type) == "array" then
      .preferences | map("- [" + (.subject // "pref") + "] " + (.content // .value // "")) | join("\n")
    else ""
    end
  ' "$file" 2>/dev/null | head -c "$max"
}

# Extract subject labels (newline-separated) from a tier response file.
agent_brain_tier_subjects() {
  local file="$1"
  [[ ! -s "$file" ]] && return 0
  jq -r '
    (if type == "array" then .
     elif (.memories // empty | type) == "array" then .memories
     elif (.preferences // empty | type) == "array" then .preferences
     else []
     end) | .[].subject_raw // .[].subject // empty
  ' "$file" 2>/dev/null | grep -v '^$' || true
}

# Merge three tier temp files into one context block (<=4800 chars).
# Agent tier is first and never truncated. Project tier is truncated first.
# Usage: agent_brain_build_skill_block <agent_file> <user_file> <project_file>
agent_brain_build_skill_block() {
  local tmp_a="$1" tmp_u="$2" tmp_p="$3"
  local MAX_TIER=1600 MAX_TOTAL=4800
  local block="" text section remaining

  text=$(agent_brain_tier_text "$tmp_a" $MAX_TIER)
  if [[ -n "$text" ]]; then
    block="## Agent context"$'\n'"$text"$'\n\n'
  fi

  text=$(agent_brain_tier_text "$tmp_u" $MAX_TIER)
  if [[ -n "$text" && ${#block} -lt $MAX_TOTAL ]]; then
    section="## Your profile"$'\n'"$text"
    remaining=$(( MAX_TOTAL - ${#block} ))
    if (( ${#section} > remaining )); then
      section=$(printf '%s' "$section" | head -c "$remaining")
    fi
    block+="$section"$'\n\n'
  fi

  text=$(agent_brain_tier_text "$tmp_p" $MAX_TIER)
  if [[ -n "$text" && ${#block} -lt $MAX_TOTAL ]]; then
    section="## Project context"$'\n'"$text"
    remaining=$(( MAX_TOTAL - ${#block} ))
    if (( ${#section} > remaining )); then
      section=$(printf '%s' "$section" | head -c "$remaining")
    fi
    block+="$section"$'\n\n'
  fi

  # Strip trailing newlines
  printf '%s' "$block" | sed -E 's/[[:space:]]+$//'
}

# Write subject labels from all tiers to /tmp for recall exclusion.
# Usage: agent_brain_collect_subjects <agent_file> <user_file> <project_file>
agent_brain_collect_subjects() {
  local subjects_file="/tmp/agent-brain-subjects-${NIGHTHAWK_SESSION_ID:-default}"
  {
    agent_brain_tier_subjects "$1"
    agent_brain_tier_subjects "$2"
    agent_brain_tier_subjects "$3"
  } | grep -v '^$' | sort -u > "$subjects_file" 2>/dev/null || true
}

# Path for the one-shot skill block file (read+deleted by first recall invocation).
# Used by hooks that cannot emit additionalContext from session-start (e.g. Cursor).
agent_brain_skill_block_file() {
  echo "/tmp/agent-brain-skill-block-${NIGHTHAWK_SESSION_ID:-default}"
}
