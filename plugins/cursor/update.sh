#!/usr/bin/env bash
# Update Agent Brain Cursor plugin files (hooks + skills) in place.
# No credentials needed — syncs scripts and skills only, not config or binaries.
#
# Usage:
#   ./plugins/cursor/update.sh [--global | --project]
#
# Remote (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/cursor/update.sh | bash
set -euo pipefail

PLUGIN_GITHUB_REPO="${AGENT_PLUGINS_GITHUB_REPO:-realnighthawk/agent-plugins}"
AGENT_PLUGINS_REF="${AGENT_PLUGINS_REF:-main}"

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

SCOPE="global"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)  SCOPE="global"; shift ;;
    --project) SCOPE="project"; shift ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ "$SCOPE" == "global" ]]; then
  CURSOR_DIR="${HOME}/.cursor"
else
  CURSOR_DIR="${PWD}/.cursor"
fi

sync_files() {
  local src tmpdir=""
  if [[ -n "${LOCAL_CHECKOUT}" ]]; then
    src="${LOCAL_CHECKOUT}/plugins/cursor"
  else
    tmpdir=$(mktemp -d)
    local url
    if [[ "$AGENT_PLUGINS_REF" == v* ]]; then
      url="https://github.com/${PLUGIN_GITHUB_REPO}/archive/refs/tags/${AGENT_PLUGINS_REF}.tar.gz"
    else
      url="https://github.com/${PLUGIN_GITHUB_REPO}/archive/refs/heads/${AGENT_PLUGINS_REF}.tar.gz"
    fi
    echo "Fetching cursor plugin files from GitHub..."
    curl -fsSL "$url" | tar -xz -C "$tmpdir"
    src="$(ls -d "$tmpdir"/*/plugins/cursor)"
  fi

  cp -R "${src}/hooks/"*.sh "${CURSOR_DIR}/hooks/"
  cp -R "${src}/hooks/lib/"*.sh "${CURSOR_DIR}/hooks/lib/"
  chmod +x "${CURSOR_DIR}/hooks/"*.sh "${CURSOR_DIR}/hooks/lib/"*.sh
  if [[ -d "${src}/skills" ]]; then
    # shellcheck source=scripts/lib/copy-skills.sh
    source "${src}/scripts/lib/copy-skills.sh"
    copy_plugin_skills "${src}/skills" "${CURSOR_DIR}/skills"
  fi
  if [[ -d "${src}/scripts" ]]; then
    mkdir -p "${CURSOR_DIR}/scripts/lib"
    cp "${src}/scripts/"*.py "${CURSOR_DIR}/scripts/" 2>/dev/null || true
    cp "${src}/scripts/"*.sh "${CURSOR_DIR}/scripts/" 2>/dev/null || true
    cp "${src}/scripts/lib/"*.sh "${CURSOR_DIR}/scripts/lib/" 2>/dev/null || true
    chmod +x "${CURSOR_DIR}/scripts/"*.sh "${CURSOR_DIR}/scripts/lib/"*.sh 2>/dev/null || true
    chmod +x "${CURSOR_DIR}/scripts/"*.py 2>/dev/null || true
  fi
  [[ -n "$tmpdir" ]] && rm -rf "$tmpdir"
}

echo "Syncing Cursor plugin files (${SCOPE})..."
sync_files

echo ""
echo "Updated Agent Brain Cursor plugin"
echo "  Scope: ${SCOPE}  Dir: ${CURSOR_DIR}"
echo "Restart Cursor to pick up hook changes."
