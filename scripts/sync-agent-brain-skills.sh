#!/usr/bin/env bash
# Assemble platform agent-brain skills from shared write-protocol fragment.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="${ROOT}/plugins/shared/write-protocol.md"

if [[ ! -f "$SHARED" ]]; then
  echo "missing ${SHARED}" >&2
  exit 1
fi

assemble() {
  local header_file="$1" dest="$2"
  { cat "$header_file"; echo ""; cat "$SHARED"; } > "$dest"
  echo "  wrote ${dest}"
}

assemble "${ROOT}/plugins/claude-code/skills/agent-brain/HEADER.md" \
  "${ROOT}/plugins/claude-code/skills/agent-brain/SKILL.md"
assemble "${ROOT}/plugins/cursor/skills/agent-brain/HEADER.md" \
  "${ROOT}/plugins/cursor/skills/agent-brain/SKILL.md"
assemble "${ROOT}/plugins/openclaw/skills/HEADER.md" \
  "${ROOT}/plugins/openclaw/skills/agent-brain-openclaw.md"

echo "Done."
