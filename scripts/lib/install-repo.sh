#!/usr/bin/env bash
# Resolve agent-plugins repo root from a plugin install.sh path, or shallow-clone for curl|bash.
# Source this file, then: plugins_install_setup <plugin> [install.sh path]
set -euo pipefail

# Sets PLUGINS_ROOT and PLUGIN_DIR. When install_script_path is empty (curl | bash), clones to
# ~/.local/share/agent-plugins and uses the plugin install.sh path inside the clone.
plugins_install_setup() {
  local plugin="$1"
  local script_path="${2:-}"

  if [[ -z "${script_path}" ]]; then
    local dest="${AGENT_PLUGINS_INSTALL_DIR:-${HOME}/.local/share/agent-plugins}"
    local repo="${AGENT_PLUGINS_REPO:-https://github.com/realnighthawk/agent-plugins.git}"
    local ref="${AGENT_PLUGINS_REF:-main}"
    if [[ ! -f "${dest}/go.mod" ]]; then
      echo "agent-plugins: cloning to ${dest} ..." >&2
      mkdir -p "$(dirname "${dest}")"
      git clone --depth 1 --branch "${ref}" "${repo}" "${dest}"
    fi
    script_path="${dest}/plugins/${plugin}/install.sh"
  fi

  PLUGINS_ROOT="$(plugins_repo_root "${script_path}")"
  PLUGIN_DIR="${PLUGINS_ROOT}/plugins/${plugin}"
}

plugins_repo_root() {
  local script_path="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${script_path}")" && pwd)"
  local candidate
  candidate="$(cd "${script_dir}/../.." && pwd)"
  if [[ -f "${candidate}/go.mod" && -f "${candidate}/cmd/mcp-call/main.go" ]]; then
    echo "${candidate}"
    return 0
  fi

  local dest="${AGENT_PLUGINS_INSTALL_DIR:-${HOME}/.local/share/agent-plugins}"
  local repo="${AGENT_PLUGINS_REPO:-https://github.com/realnighthawk/agent-plugins.git}"
  local ref="${AGENT_PLUGINS_REF:-main}"
  if [[ ! -f "${dest}/go.mod" ]]; then
    echo "agent-plugins: cloning to ${dest} ..." >&2
    mkdir -p "$(dirname "${dest}")"
    git clone --depth 1 --branch "${ref}" "${repo}" "${dest}"
  fi
  echo "${dest}"
}

# Back-compat alias for install scripts sourced before rename.
agent_brain_repo_root() {
  plugins_repo_root "$1"
}
