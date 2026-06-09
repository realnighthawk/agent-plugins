#!/usr/bin/env bash
# Update Agent Brain Cursor plugin — removes the existing install and reinstalls fresh.
# Credentials can be passed on the command line or loaded from agent-brain.env.
#
# Usage:
#   ./plugins/cursor/update.sh [--scope global|project] [--url URL] [--agent-id ID] [--api-key KEY | --jwt TOKEN]
#
# Remote (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/cursor/update.sh | bash -s -- --api-key YOUR_KEY
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
PASSTHROUGH=()
HAS_API_KEY=0
HAS_JWT=0

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --url URL           MCP server URL
  --agent-id ID       Agent ID
  --api-key KEY       API key (or load from agent-brain.env)
  --jwt TOKEN         JWT token (or load from agent-brain.env)
  --user USER         User identifier for memory scoping
  --scope SCOPE       global (default) or project
  --global            Update ~/.cursor (same as --scope global)
  --project           Update ./.cursor (same as --scope project)
  --version VERSION   Plugin version label
  -h, --help          Show this help
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      SCOPE="$2"
      PASSTHROUGH+=("$1" "$2")
      shift 2
      ;;
    --global)
      SCOPE="global"
      PASSTHROUGH+=("$1")
      shift
      ;;
    --project)
      SCOPE="project"
      PASSTHROUGH+=("$1")
      shift
      ;;
    --api-key) HAS_API_KEY=1; PASSTHROUGH+=("$1" "$2"); shift 2 ;;
    --jwt) HAS_JWT=1; PASSTHROUGH+=("$1" "$2"); shift 2 ;;
    --url|--agent-id|--user|--version)
      PASSTHROUGH+=("$1" "$2")
      shift 2
      ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

if [[ "$HAS_API_KEY" -eq 0 && "$HAS_JWT" -eq 0 ]]; then
  if [[ -n "${LOCAL_CHECKOUT}" ]]; then
    PLUGIN_DIR="${LOCAL_CHECKOUT}/plugins/cursor"
    # shellcheck source=lib/plugin-install.sh
    . "${PLUGIN_DIR}/lib/plugin-install.sh"
    if load_cursor_plugin_env "$SCOPE"; then
      [[ -n "${NIGHTHAWK_API_KEY:-}" ]] && PASSTHROUGH+=(--api-key "${NIGHTHAWK_API_KEY}")
      [[ -n "${NIGHTHAWK_JWT:-}" ]] && PASSTHROUGH+=(--jwt "${NIGHTHAWK_JWT}")
      [[ -n "${NIGHTHAWK_MCP_URL:-}" ]] && PASSTHROUGH+=(--url "${NIGHTHAWK_MCP_URL}")
      [[ -n "${NIGHTHAWK_AGENT_ID:-}" ]] && PASSTHROUGH+=(--agent-id "${NIGHTHAWK_AGENT_ID}")
      [[ -n "${NIGHTHAWK_USER:-}" ]] && PASSTHROUGH+=(--user "${NIGHTHAWK_USER}")
    fi
  else
    _env_file="${HOME}/.cursor/agent-brain.env"
    if [[ "$SCOPE" == "project" ]]; then
      _env_file="${PWD}/.cursor/agent-brain.env"
    fi
    if [[ -f "$_env_file" ]]; then
      # shellcheck disable=SC1090
      set -a
      source "$_env_file"
      set +a
      [[ -n "${NIGHTHAWK_API_KEY:-}" ]] && PASSTHROUGH+=(--api-key "${NIGHTHAWK_API_KEY}")
      [[ -n "${NIGHTHAWK_JWT:-}" ]] && PASSTHROUGH+=(--jwt "${NIGHTHAWK_JWT}")
      [[ -n "${NIGHTHAWK_MCP_URL:-}" ]] && PASSTHROUGH+=(--url "${NIGHTHAWK_MCP_URL}")
      [[ -n "${NIGHTHAWK_AGENT_ID:-}" ]] && PASSTHROUGH+=(--agent-id "${NIGHTHAWK_AGENT_ID}")
      [[ -n "${NIGHTHAWK_USER:-}" ]] && PASSTHROUGH+=(--user "${NIGHTHAWK_USER}")
    fi
  fi
fi

if [[ -n "${LOCAL_CHECKOUT}" ]]; then
  exec "${LOCAL_CHECKOUT}/plugins/cursor/install.sh" "${PASSTHROUGH[@]}"
else
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT
  _install="${_tmpdir}/install.sh"
  _raw_base="https://raw.githubusercontent.com/${PLUGIN_GITHUB_REPO}/${AGENT_PLUGINS_REF}"
  curl -fsSL "${_raw_base}/plugins/cursor/install.sh" -o "$_install"
  chmod +x "$_install"
  exec "$_install" "${PASSTHROUGH[@]}"
fi
