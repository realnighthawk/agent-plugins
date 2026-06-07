#!/usr/bin/env bash
# Install Agent Brain OpenClaw plugin (hosted SSE + lifecycle hooks).
#
# Usage:
#   ./plugins/openclaw/install.sh \
#     --url https://agent-memory.nighthawklabs.org/mcp \
#     --agent-id openclaw-you \
#     --api-key YOUR_KEY \
#     [--config-file ~/.openclaw/openclaw.gemini.json]
#
# Remote (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/openclaw/install.sh | bash -s -- --api-key ...
set -euo pipefail

PLUGIN_GITHUB_REPO="${AGENT_PLUGINS_GITHUB_REPO:-realnighthawk/agent-plugins}"
AGENT_PLUGINS_REF="${AGENT_PLUGINS_REF:-main}"

# Detect if running from a local checkout (dev workflow — enables go build fallback for mcp-call).
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

MCP_URL="https://agent-memory.nighthawklabs.org/mcp"
AGENT_ID=""
API_KEY="${NIGHTHAWK_API_KEY:-}"
JWT="${NIGHTHAWK_JWT:-}"
USER_TAG="${USER:-you}"
AGENT_PREFIX="openclaw"
MCP_CALL_VERSION="${MCP_CALL_VERSION:-latest}"
SKIP_PLUGIN_INSTALL=0
RESTART_GATEWAY=0
EXTRA_CONFIG_FILE=""

usage() {
  sed -n '2,11p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) MCP_URL="$2"; shift 2 ;;
    --agent-id) AGENT_ID="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --jwt) JWT="$2"; shift 2 ;;
    --user) USER_TAG="$2"; shift 2 ;;
    --agent-prefix) AGENT_PREFIX="$2"; shift 2 ;;
    --version) MCP_CALL_VERSION="$2"; shift 2 ;;
    --config-file) EXTRA_CONFIG_FILE="$2"; shift 2 ;;
    --skip-plugin-install) SKIP_PLUGIN_INSTALL=1; shift ;;
    --restart) RESTART_GATEWAY=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown arg: $1" >&2; usage 1 ;;
  esac
done

if [[ -z "$AGENT_ID" ]]; then
  AGENT_ID="${AGENT_PREFIX}-${USER_TAG}"
fi

if [[ -z "$API_KEY" && -z "$JWT" ]]; then
  echo "Provide --api-key or --jwt (or set NIGHTHAWK_API_KEY / NIGHTHAWK_JWT)." >&2
  exit 1
fi

ENV_DIR="${HOME}/.config/agent-brain"
ENV_FILE="${ENV_DIR}/openclaw.env"
OPENCLAW_CONFIG="${HOME}/.openclaw/openclaw.json"
mkdir -p "$ENV_DIR" "$(dirname "$OPENCLAW_CONFIG")"

# Resolve plugin directory: local checkout (dev) or git clone (remote).
# OpenClaw's --link needs a stable on-disk path that persists after install.
# Using git clone means re-running install.sh updates the plugin in place.
resolve_plugin_dir() {
  if [[ -n "${LOCAL_CHECKOUT}" ]]; then
    echo "${LOCAL_CHECKOUT}/plugins/openclaw"
    return
  fi

  local repo_dest="${HOME}/.local/share/agent-brain/agent-plugins"
  local repo_url="https://github.com/${PLUGIN_GITHUB_REPO}.git"

  if [[ -d "${repo_dest}/.git" ]]; then
    echo "Updating agent-plugins repo at ${repo_dest}..." >&2
    git -C "$repo_dest" fetch --depth=1 origin "${AGENT_PLUGINS_REF}" >&2
    git -C "$repo_dest" checkout FETCH_HEAD >&2
  else
    echo "Cloning agent-plugins repo to ${repo_dest}..." >&2
    mkdir -p "$(dirname "$repo_dest")"
    git clone --depth=1 --branch "${AGENT_PLUGINS_REF}" "$repo_url" "$repo_dest" >&2
  fi

  echo "${repo_dest}/plugins/openclaw"
}

# Install mcp-call binary to DEST.
# Local dev checkouts delegate to the full fetch script (supports go build fallback).
# Remote installs download directly from GitHub releases.
install_mcp_call() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"

  if [[ -n "${LOCAL_CHECKOUT}" && -f "${LOCAL_CHECKOUT}/scripts/fetch-mcp-call.sh" ]]; then
    export MCP_CALL_VERSION
    "${LOCAL_CHECKOUT}/scripts/fetch-mcp-call.sh" "$dest"
    return
  fi

  local os_name arch asset repo ver url tmp
  case "$(uname -s)" in
    Darwin) os_name=darwin ;;
    Linux)  os_name=linux ;;
    *) echo "unsupported OS: $(uname -s)" >&2; return 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) echo "unsupported arch: $(uname -m)" >&2; return 1 ;;
  esac

  asset="mcp-call-${os_name}-${arch}"
  repo="${NIGHTHAWK_MCP_CALL_REPO:-realnighthawk/agent-plugins}"
  ver="${MCP_CALL_VERSION:-latest}"
  if [[ -z "$ver" || "$ver" == "latest" ]]; then
    url="https://github.com/${repo}/releases/latest/download/${asset}"
  else
    url="https://github.com/${repo}/releases/download/v${ver#v}/${asset}"
  fi

  tmp="${dest}.$$.tmp"
  echo "Downloading mcp-call (${asset})..."
  curl -fsSL "$url" -o "$tmp"
  chmod +x "$tmp"
  mv -f "$tmp" "$dest"
  echo "Installed ${dest} from release"
}

ingest_agent_skills() {
  local skills_dir="${PLUGIN_DIR}/skills"
  [[ -d "$skills_dir" ]] || return 0
  local bin="${PLUGIN_DIR}/bin/mcp-call"
  [[ -x "$bin" ]] || return 0

  local ok=0 fail=0
  for skill_file in "${skills_dir}"/*.md; do
    [[ -f "$skill_file" ]] || continue
    local name body description args
    name=$(basename "$skill_file" .md)
    body=$(cat "$skill_file")
    description=$(head -n1 "$skill_file" | sed 's/^#[[:space:]]*//')
    args=$(jq -nc \
      --arg aid "$AGENT_ID" --arg name "$name" \
      --arg body "$body" --arg desc "$description" \
      '{agent_id:$aid,name:$name,body:$body,description:$desc}')
    if [[ -n "$JWT" ]]; then
      NIGHTHAWK_JWT="$JWT" NIGHTHAWK_MCP_URL="$MCP_URL" \
        NIGHTHAWK_AGENT_ID="$AGENT_ID" NIGHTHAWK_MCP_CALL="$bin" \
        "$bin" ingest_skill "$args" >/dev/null 2>&1 && ok=$(( ok+1 )) || fail=$(( fail+1 ))
    else
      NIGHTHAWK_API_KEY="$API_KEY" NIGHTHAWK_MCP_URL="$MCP_URL" \
        NIGHTHAWK_AGENT_ID="$AGENT_ID" NIGHTHAWK_MCP_CALL="$bin" \
        "$bin" ingest_skill "$args" >/dev/null 2>&1 && ok=$(( ok+1 )) || fail=$(( fail+1 ))
    fi
  done
  echo "Agent skills ingested: ${ok} ok, ${fail} failed"
}

PLUGIN_DIR="$(resolve_plugin_dir)"

echo "Installing mcp-call..."
install_mcp_call "${PLUGIN_DIR}/bin/mcp-call"

cat >"$ENV_FILE" <<EOF
# Agent Brain OpenClaw — generated by install.sh
export NIGHTHAWK_MCP_URL=${MCP_URL}
export NIGHTHAWK_AGENT_ID=${AGENT_ID}
export NIGHTHAWK_AGENT_PREFIX=${AGENT_PREFIX}
EOF
chmod 600 "$ENV_FILE"

if [[ -n "$JWT" ]]; then
  echo "export NIGHTHAWK_JWT=${JWT}" >>"$ENV_FILE"
else
  echo "export NIGHTHAWK_API_KEY=${API_KEY}" >>"$ENV_FILE"
fi

# Write plugin config into openclaw.json BEFORE --link so OpenClaw's schema
# validation passes (configSchema requires url). Do NOT pre-write
# plugins.slots.memory — openclaw sets it automatically during install and
# will reject it if the plugin isn't registered yet.
merge_openclaw_config() {
  local target_file="$1"
  local auth_key
  if [[ -n "$JWT" ]]; then
    auth_key="jwt"
  else
    auth_key="apiKey"
  fi

  local base='{}'
  if [[ -f "$target_file" ]]; then
    base="$(cat "$target_file")"
  fi

  echo "$base" | jq \
    --arg auth_key "$auth_key" \
    '
    .plugins = (.plugins // {}) |
    .plugins.entries = (.plugins.entries // {}) |
    .plugins.entries["agent-brain"] = {
      enabled: true,
      config: ({
        url: "${NIGHTHAWK_MCP_URL}",
        agentId: "${NIGHTHAWK_AGENT_ID}",
        autoRecall: true,
        autoCapture: true,
        recallLimit: 8
      } + (if $auth_key == "jwt" then {jwt: "${NIGHTHAWK_JWT}"} else {apiKey: "${NIGHTHAWK_API_KEY}"} end))
    }
    ' >"${target_file}.tmp" && mv "${target_file}.tmp" "$target_file"

  echo "Updated ${target_file}"
}

merge_openclaw_config "$OPENCLAW_CONFIG"

if [[ -n "$EXTRA_CONFIG_FILE" ]]; then
  if [[ ! -f "$EXTRA_CONFIG_FILE" ]]; then
    echo "Error: --config-file path does not exist: ${EXTRA_CONFIG_FILE}" >&2
    exit 1
  fi
  merge_openclaw_config "$EXTRA_CONFIG_FILE"
fi

echo "Ingesting agent-tier skills..."
ingest_agent_skills

if [[ "$SKIP_PLUGIN_INSTALL" -eq 0 ]]; then
  echo "Linking plugin with OpenClaw..."
  openclaw plugins install --link "${PLUGIN_DIR}"
fi

if [[ "$RESTART_GATEWAY" -eq 1 ]]; then
  echo "Restarting OpenClaw gateway..."
  openclaw gateway restart
fi

echo ""
echo "Installed Agent Brain for OpenClaw"
echo "  Plugin path: ${PLUGIN_DIR}"
echo "  MCP URL:     ${MCP_URL}"
echo "  Agent ID:    ${AGENT_ID}"
echo "  Env file:    ${ENV_FILE}"
echo "  Config:      ${OPENCLAW_CONFIG}"
if [[ -n "$EXTRA_CONFIG_FILE" ]]; then
  echo "  Extra config: ${EXTRA_CONFIG_FILE}"
fi
echo ""
echo "Re-ingest skills after updates: source ${ENV_FILE} && ${PLUGIN_DIR}/bin/mcp-call ingest_skill ..."
echo "Optional: source ${ENV_FILE} in your shell for env-based overrides."
echo ""
echo "Server checklist:"
echo "  1. Memory Explorer → Settings: register agent \"${AGENT_ID}\""
echo "  2. openclaw gateway restart"
echo "  3. openclaw plugins inspect agent-brain --runtime --json"
