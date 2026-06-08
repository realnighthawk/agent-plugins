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

_script_path="${BASH_SOURCE[0]:-}"
_plugin_dir="$(cd "$(dirname "${_script_path}")" 2>/dev/null && pwd)"

# Delegate to install.sh with --skip-plugin-add so we skip the slow
# marketplace remove/add/reinstall but still refresh mcp-call and MCP config.
exec "${_plugin_dir}/install.sh" --skip-plugin-add "$@"
