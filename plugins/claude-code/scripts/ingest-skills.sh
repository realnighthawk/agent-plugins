#!/usr/bin/env bash
# Ingest agent-tier skills into agent-brain server.
# Run once after install, and again whenever skill files are updated.
#
# Usage:
#   NIGHTHAWK_AGENT_ID=claude-you ./scripts/ingest-skills.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

if [[ -z "${NIGHTHAWK_MCP_URL:-}" ]]; then
  echo "NIGHTHAWK_MCP_URL not set — source your env file first." >&2
  exit 1
fi
if [[ -z "${NIGHTHAWK_AGENT_ID:-}" ]]; then
  echo "NIGHTHAWK_AGENT_ID not set — source your env file first." >&2
  exit 1
fi

SKILLS_DIR="${SCRIPT_DIR}/../skills"
if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "No skills directory found at ${SKILLS_DIR}" >&2
  exit 0
fi

ok=0
fail=0

for skill_file in "${SKILLS_DIR}"/*.md; do
  [[ -f "$skill_file" ]] || continue
  name=$(basename "$skill_file" .md)
  body=$(cat "$skill_file")
  description=$(head -n1 "$skill_file" | sed 's/^#\s*//')

  args=$(jq -nc \
    --arg aid "${NIGHTHAWK_AGENT_ID}" \
    --arg name "$name" \
    --arg body "$body" \
    --arg desc "$description" \
    '{agent_id:$aid, name:$name, body:$body, description:$desc}')

  if agent_brain_mcp_call ingest_skill "$args" >/dev/null 2>&1; then
    echo "  ingested: $name"
    ok=$(( ok + 1 ))
  else
    echo "  failed:   $name" >&2
    fail=$(( fail + 1 ))
  fi
done

echo ""
echo "Skills ingested: ${ok}, failed: ${fail}"
[[ "$fail" -eq 0 ]]
