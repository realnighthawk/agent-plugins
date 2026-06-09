#!/usr/bin/env bash
# Install Agent Brain Cursor plugin (hooks, skills, mcp-call, MCP config).
#
# Usage:
#   ./plugins/cursor/install.sh --api-key YOUR_KEY [--url URL] [--agent-id ID] [--scope global|project]
#
# Remote (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/cursor/install.sh | bash -s -- --api-key YOUR_KEY
set -euo pipefail

PLUGIN_GITHUB_REPO="${AGENT_PLUGINS_GITHUB_REPO:-realnighthawk/agent-plugins}"
AGENT_PLUGINS_REF="${AGENT_PLUGINS_REF:-main}"

_script_path="${BASH_SOURCE[0]:-}"
if [[ -n "${_script_path}" ]]; then
  _lib="$(cd "$(dirname "${_script_path}")/../.." 2>/dev/null && pwd)/scripts/lib/install-repo.sh"
  if [[ -f "${_lib}" ]]; then
    # shellcheck source=../../scripts/lib/install-repo.sh
    . "${_lib}"
    plugins_install_setup cursor "${_script_path}"
  fi
fi
PLUGIN_DIR="${PLUGIN_DIR:-}"
PLUGINS_ROOT="${PLUGINS_ROOT:-}"

URL="${NIGHTHAWK_MCP_URL:-https://agent-brain.nighthawk.systems/mcp}"
AGENT_ID="${NIGHTHAWK_AGENT_ID:-default}"
API_KEY=""
JWT=""
USER="${NIGHTHAWK_USER:-}"
SCOPE="global"
VERSION="0.1.3"
SKIP_PLUGIN_REMOVE=0

usage() {
  cat <<EOF
Usage: $0 --api-key KEY | --jwt TOKEN [options]

Options:
  --url URL           MCP server URL (default: ${URL})
  --agent-id ID       Agent ID (default: ${AGENT_ID})
  --api-key KEY       API key (required unless --jwt)
  --jwt TOKEN         JWT token (required unless --api-key)
  --user USER         User identifier for memory scoping
  --scope SCOPE       global (default) or project
  --global            Install to ~/.cursor (same as --scope global)
  --project           Install to ./.cursor (same as --scope project)
  --version VERSION   Plugin version label (default: ${VERSION})
  --skip-plugin-remove  Skip removing an existing install before reinstalling
  -h, --help          Show this help
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --agent-id) AGENT_ID="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --jwt) JWT="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --scope)
      SCOPE="$2"
      if [[ "$SCOPE" != "global" && "$SCOPE" != "project" ]]; then
        echo "Error: --scope must be global or project" >&2
        exit 1
      fi
      shift 2
      ;;
    --global) SCOPE="global"; shift ;;
    --project) SCOPE="project"; shift ;;
    --version) VERSION="$2"; shift 2 ;;
    --skip-plugin-remove) SKIP_PLUGIN_REMOVE=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

if [[ -z "$API_KEY" && -z "$JWT" ]]; then
  echo "Error: --api-key or --jwt is required" >&2
  exit 1
fi

if [[ -z "$PLUGIN_DIR" || -z "$PLUGINS_ROOT" ]]; then
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT
  _raw_base="https://raw.githubusercontent.com/${PLUGIN_GITHUB_REPO}/${AGENT_PLUGINS_REF}"
  git clone --depth 1 --branch "${AGENT_PLUGINS_REF}" \
    "https://github.com/${PLUGIN_GITHUB_REPO}.git" "${_tmpdir}/agent-plugins"
  PLUGINS_ROOT="${_tmpdir}/agent-plugins"
  PLUGIN_DIR="${PLUGINS_ROOT}/plugins/cursor"
fi

# shellcheck source=lib/plugin-install.sh
. "${PLUGIN_DIR}/lib/plugin-install.sh"

cursor_dir="$(cursor_plugin_scope_dir "$SCOPE")"
if [[ "$SKIP_PLUGIN_REMOVE" -eq 0 ]]; then
  remove_cursor_plugin "$cursor_dir"
fi

install_cursor_plugin "$SCOPE" "$URL" "$AGENT_ID" "$API_KEY" "$JWT" "$USER" "$VERSION"
