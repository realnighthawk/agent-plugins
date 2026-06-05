#!/usr/bin/env bash
# Shared helpers for Agent Brain Cursor hooks.

agent_brain_load_env() {
  local f
  for f in \
    "${CURSOR_PROJECT_DIR:+$CURSOR_PROJECT_DIR/.cursor/agent-brain.env}" \
    "${HOME}/.cursor/agent-brain.env"; do
    if [[ -n "$f" && -f "$f" ]]; then
      set -a
      # shellcheck source=/dev/null
      source "$f"
      set +a
      return 0
    fi
  done
  return 1
}

agent_brain_state_dir() {
  if [[ -n "${CURSOR_PROJECT_DIR:-}" && -d "${CURSOR_PROJECT_DIR}/.cursor" ]]; then
    echo "${CURSOR_PROJECT_DIR}/.cursor/state"
  else
    echo "${HOME}/.cursor/state"
  fi
}

agent_brain_session_file() {
  echo "$(agent_brain_state_dir)/agent-brain-session"
}

agent_brain_load_session() {
  local f
  f="$(agent_brain_session_file)"
  if [[ -f "$f" ]]; then
    cat "$f"
  fi
}

agent_brain_save_session() {
  local id="$1"
  mkdir -p "$(agent_brain_state_dir)"
  printf '%s' "$id" > "$(agent_brain_session_file)"
  export NIGHTHAWK_SESSION_ID="$id"
}

agent_brain_resolve_mcp_call() {
  if [[ -n "${NIGHTHAWK_MCP_CALL:-}" && -x "${NIGHTHAWK_MCP_CALL}" ]]; then
    echo "${NIGHTHAWK_MCP_CALL}"
    return 0
  fi
  local hook_dir
  hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ -x "${hook_dir}/../bin/mcp-call" ]]; then
    echo "${hook_dir}/../bin/mcp-call"
    return 0
  fi
  if [[ -x "${hook_dir}/../../plugins/cursor/bin/mcp-call" ]]; then
    echo "${hook_dir}/../../plugins/cursor/bin/mcp-call"
    return 0
  fi
  return 1
}

agent_brain_mcp_call() {
  local tool="$1"
  local args="${2:-}"
  [[ -z "$args" ]] && args="{}"
  local bin
  if ! bin="$(agent_brain_resolve_mcp_call)"; then
    echo "agent-brain: mcp-call not found; run: curl install.sh or ./scripts/fetch-mcp-call.sh ~/.cursor/bin/mcp-call" >&2
    return 1
  fi
  "$bin" "$tool" "$args"
}
