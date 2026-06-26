#!/usr/bin/env bash
# Assemble memory-write skill from shared fragments.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="${ROOT}/plugins/shared"
DECISIONS="${SHARED}/memory-write-decisions.md"
PAYLOAD="${SHARED}/memory-write-payload.md"

for f in "$DECISIONS" "$PAYLOAD"; do
  if [[ ! -f "$f" ]]; then
    echo "missing ${f}" >&2
    exit 1
  fi
done

assemble() {
  local header_file="$1" dest="$2"
  { cat "$header_file"; echo ""; cat "$DECISIONS"; echo ""; cat "$PAYLOAD"; } > "$dest"
  echo "  wrote ${dest}"
}

assemble "${ROOT}/plugins/claude-code/skills/memory-write/HEADER.md" \
  "${ROOT}/plugins/claude-code/skills/memory-write/SKILL.md"

echo "Done."
