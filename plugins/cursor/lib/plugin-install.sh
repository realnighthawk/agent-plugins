#!/usr/bin/env bash
# Shared install/remove helpers for the Cursor Agent Brain plugin.
# Source from install.sh / update.sh after setting PLUGIN_DIR and PLUGINS_ROOT.

AGENT_BRAIN_SKILL_NAMES=(agent-brain replay-memory)
AGENT_BRAIN_HOOK_FILES=(session-start.sh recall.sh index.sh)

cursor_plugin_scope_dir() {
  local scope="$1"
  if [[ "$scope" == "project" ]]; then
    echo "${PWD}/.cursor"
  else
    echo "${HOME}/.cursor"
  fi
}

remove_cursor_plugin() {
  local dir="$1"
  echo "Removing existing Agent Brain Cursor plugin from ${dir}..."

  local hook
  for hook in "${AGENT_BRAIN_HOOK_FILES[@]}"; do
    rm -f "${dir}/hooks/${hook}"
  done
  rm -rf "${dir}/hooks/lib"

  local skill
  for skill in "${AGENT_BRAIN_SKILL_NAMES[@]}"; do
    rm -rf "${dir}/skills/${skill}"
  done

  rm -rf "${dir}/scripts"
  rm -f "${dir}/bin/mcp-call"
  rm -f "${dir}/agent-brain.env"

  if [[ -f "${dir}/mcp.json" ]] && command -v jq &>/dev/null; then
    local tmp
    tmp=$(mktemp)
    if jq 'del(.mcpServers["agent-brain"])' "${dir}/mcp.json" >"$tmp" 2>/dev/null; then
      mv "$tmp" "${dir}/mcp.json"
    else
      rm -f "$tmp"
    fi
  fi

  if [[ -f "${dir}/hooks.json" ]]; then
    rm -f "${dir}/hooks.json"
  fi
}

fetch_plugin_files() {
  local src="$1" dest="$2"
  # shellcheck source=../scripts/lib/copy-skills.sh
  . "${src}/scripts/lib/copy-skills.sh"
  mkdir -p "${dest}/hooks" "${dest}/skills" "${dest}/scripts/lib"
  cp "${src}/hooks/"*.sh "${dest}/hooks/"
  cp -r "${src}/hooks/lib" "${dest}/hooks/"
  copy_plugin_skills "${src}/skills" "${dest}/skills"
  cp "${src}/scripts/extract_conversations.py" "${dest}/scripts/"
  cp "${src}/scripts/lib/copy-skills.sh" "${dest}/scripts/lib/"
  chmod +x "${dest}/hooks/"*.sh 2>/dev/null || true
}

install_mcp_call() {
  local plugins_root="$1" dest="$2"
  if ! command -v go &>/dev/null; then
    echo "Error: go is required to build mcp-call. Install Go or set PATH." >&2
    exit 1
  fi
  mkdir -p "${dest}/bin"
  (cd "${plugins_root}" && go build -o "${dest}/bin/mcp-call" ./cmd/mcp-call)
  chmod +x "${dest}/bin/mcp-call"
}

write_agent_brain_env() {
  local env_file="$1" url="$2" agent_id="$3" api_key="$4" jwt="$5" user="$6"
  mkdir -p "$(dirname "$env_file")"
  cat >"$env_file" <<EOF
NIGHTHAWK_MCP_URL=${url}
NIGHTHAWK_AGENT_ID=${agent_id}
NIGHTHAWK_API_KEY=${api_key}
NIGHTHAWK_JWT=${jwt}
NIGHTHAWK_USER=${user}
EOF
  chmod 600 "$env_file"
}

write_hooks_json() {
  local hooks_file="$1" template="$2" mcp_call="$3"
  sed "s|__MCP_CALL__|${mcp_call}|g" "$template" >"$hooks_file"
}

merge_mcp_json() {
  local mcp_file="$1" url="$2" agent_id="$3" api_key="$4" env_file="$5"
  local entry
  entry=$(cat <<EOF
{
  "type": "http",
  "url": "${url}",
  "headers": {
    "X-API-Key": "${api_key}",
    "X-Agent-ID": "${agent_id}",
    "X-Session-ID": "\${NIGHTHAWK_SESSION_ID}"
  },
  "envFile": "${env_file}"
}
EOF
)
  if [[ ! -f "$mcp_file" ]]; then
    echo "{\"mcpServers\": {\"agent-brain\": ${entry}}}" | jq . >"$mcp_file"
  else
    local tmp
    tmp=$(mktemp)
    jq --argjson entry "$entry" '.mcpServers["agent-brain"] = $entry' "$mcp_file" >"$tmp"
    mv "$tmp" "$mcp_file"
  fi
}

install_cursor_plugin() {
  local scope="$1" url="$2" agent_id="$3" api_key="$4" jwt="$5" user="$6" version="$7"
  local cursor_dir
  cursor_dir="$(cursor_plugin_scope_dir "$scope")"
  local mcp_call="${cursor_dir}/bin/mcp-call"

  mkdir -p "${cursor_dir}/hooks" "${cursor_dir}/skills" "${cursor_dir}/bin"
  fetch_plugin_files "${PLUGIN_DIR}" "${cursor_dir}"
  install_mcp_call "${PLUGINS_ROOT}" "${cursor_dir}"

  write_agent_brain_env \
    "${cursor_dir}/agent-brain.env" "$url" "$agent_id" "$api_key" "$jwt" "$user"
  write_hooks_json \
    "${cursor_dir}/hooks.json" "${PLUGIN_DIR}/templates/hooks.json" "$mcp_call"
  merge_mcp_json \
    "${cursor_dir}/mcp.json" "$url" "$agent_id" "$api_key" "${cursor_dir}/agent-brain.env"

  echo ""
  echo "Agent Brain Cursor plugin installed (${version}, scope=${scope})"
  echo "  hooks:    ${cursor_dir}/hooks.json"
  echo "  mcp:      ${cursor_dir}/mcp.json"
  echo "  env:      ${cursor_dir}/agent-brain.env"
  echo "  mcp-call: ${mcp_call}"
  echo ""
  echo "Restart Cursor to load hooks and MCP."
}

load_cursor_plugin_env() {
  local scope="$1"
  local env_file
  env_file="$(cursor_plugin_scope_dir "$scope")/agent-brain.env"
  if [[ ! -f "$env_file" ]]; then
    return 1
  fi
  # shellcheck disable=SC1090
  set -a
  source "$env_file"
  set +a
  return 0
}
