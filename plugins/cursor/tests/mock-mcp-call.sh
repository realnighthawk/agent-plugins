#!/usr/bin/env bash
set -euo pipefail
echo "$1 $2" >> "${NIGHTHAWK_MOCK_CALL_LOG:-/dev/null}"
case "${1:-}" in
  memory_search)
    echo '[{"subject_raw":"diet","content":"vegetarian","confidence":0.9}]'
    ;;
  memory_write)
    touch "${NIGHTHAWK_MOCK_INDEX_MARKER:-/tmp/agent-brain-index-called}"
    echo '{"memory_id":"00000000-0000-0000-0000-000000000001"}'
    ;;
  memory_preference_profile)
    echo '[{"subject_raw":"communication","content":"prefers terse responses","confidence":0.9}]'
    ;;
  retrieve_skills_for_context)
    echo '{"content":"Use memory_write for durable facts. Tool discipline: never store locally."}'
    ;;
  *)
    echo "unknown tool: $1" >&2
    exit 1
    ;;
esac
