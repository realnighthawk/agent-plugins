#!/usr/bin/env bash
# Update Agent Brain OpenClaw plugin in place.
# For remote installs: pulls latest from GitHub then optionally restarts the gateway.
# For local checkouts: changes are already on disk; optionally restarts the gateway.
#
# Usage:
#   ./plugins/openclaw/update.sh [--restart]
#
# Remote (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/openclaw/update.sh | bash -s -- [--restart]
set -euo pipefail

PLUGIN_GITHUB_REPO="${AGENT_PLUGINS_GITHUB_REPO:-realnighthawk/agent-plugins}"
AGENT_PLUGINS_REF="${AGENT_PLUGINS_REF:-main}"
RESTART_GATEWAY=0

_script_path="${BASH_SOURCE[0]:-}"
LOCAL_CHECKOUT=""
if [[ -n "${_script_path}" ]]; then
  _lib="$(cd "$(dirname "${_script_path}")/../.." 2>/dev/null && pwd)/scripts/lib/install-repo.sh"
  if [[ -f "${_lib}" ]]; then
    # shellcheck source=../../scripts/lib/install-repo.sh
    . "${_lib}"
    LOCAL_CHECKOUT="$(plugins_repo_root "${_script_path}")"
  fi
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --restart) RESTART_GATEWAY=1; shift ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "${LOCAL_CHECKOUT}" ]]; then
  echo "Local checkout — plugin dir is already up to date."
  PLUGIN_DIR="${LOCAL_CHECKOUT}/plugins/openclaw"
else
  repo_dest="${HOME}/.local/share/agent-brain/agent-plugins"
  if [[ ! -d "${repo_dest}/.git" ]]; then
    echo "Plugin not installed at ${repo_dest}. Run install.sh first." >&2
    exit 1
  fi
  echo "Updating agent-plugins repo at ${repo_dest}..."
  git -C "$repo_dest" fetch --depth=1 origin "${AGENT_PLUGINS_REF}"
  git -C "$repo_dest" checkout FETCH_HEAD
  PLUGIN_DIR="${repo_dest}/plugins/openclaw"
fi

if [[ "$RESTART_GATEWAY" -eq 1 ]]; then
  echo "Restarting OpenClaw gateway..."
  openclaw gateway restart
else
  echo "Run 'openclaw gateway restart' to pick up changes."
fi

echo ""
echo "Updated Agent Brain OpenClaw plugin"
echo "  Plugin dir: ${PLUGIN_DIR}"
