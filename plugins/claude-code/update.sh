#!/usr/bin/env bash
# Update Agent Brain Claude Code plugin in place.
# Skips the marketplace re-registration step — credentials still required
# to refresh mcp-call and MCP config.
#
# Usage:
#   ./plugins/claude-code/update.sh --api-key YOUR_KEY [--url URL] [--agent-id ID]
#
# Remote (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/claude-code/update.sh | bash -s -- --api-key YOUR_KEY
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

if [[ -n "${LOCAL_CHECKOUT}" ]]; then
  # Local checkout — delegate directly to install.sh
  exec "${LOCAL_CHECKOUT}/plugins/claude-code/install.sh" --skip-plugin-add "$@"
else
  # Remote — download install.sh and run it with --skip-plugin-add
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT
  _install="${_tmpdir}/install.sh"
  _raw_base="https://raw.githubusercontent.com/${PLUGIN_GITHUB_REPO}/${AGENT_PLUGINS_REF}"
  curl -fsSL "${_raw_base}/plugins/claude-code/install.sh" -o "$_install"
  chmod +x "$_install"
  exec "$_install" --skip-plugin-add "$@"
fi
