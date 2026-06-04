#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  memory_search)
    echo '[{"subject_raw":"diet","content":"vegetarian","confidence":0.9}]'
    ;;
  memory_write)
    touch "${NIGHTHAWK_MOCK_INDEX_MARKER:-/tmp/agent-brain-index-called}"
    echo '{"memory_id":"00000000-0000-0000-0000-000000000001"}'
    ;;
  memory_preference_profile)
    echo '{}'
    ;;
  *)
    echo "unknown tool: $1" >&2
    exit 1
    ;;
esac
