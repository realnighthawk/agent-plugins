#!/usr/bin/env bash
# Shared helpers for Agent Brain Claude Code plugin hooks.

agent_brain_state_dir() {
  if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    echo "${CLAUDE_PLUGIN_DATA}/state"
  elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    echo "${CLAUDE_PROJECT_DIR}/.claude/agent-brain-state"
  else
    echo "${HOME}/.claude/agent-brain-state"
  fi
}

agent_brain_session_file() {
  echo "$(agent_brain_state_dir)/agent-brain-session"
}

agent_brain_last_prompt_file() {
  echo "$(agent_brain_state_dir)/last-user-prompt"
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

agent_brain_save_last_prompt() {
  local text="$1"
  mkdir -p "$(agent_brain_state_dir)"
  printf '%s' "$text" > "$(agent_brain_last_prompt_file)"
}

agent_brain_load_last_prompt() {
  local f
  f="$(agent_brain_last_prompt_file)"
  if [[ -f "$f" ]]; then
    cat "$f"
  fi
}

agent_brain_resolve_mcp_call() {
  if [[ -n "${NIGHTHAWK_MCP_CALL:-}" && -x "${NIGHTHAWK_MCP_CALL}" ]]; then
    echo "${NIGHTHAWK_MCP_CALL}"
    return 0
  fi
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ -x "${script_dir}/../bin/mcp-call" ]]; then
    echo "${script_dir}/../bin/mcp-call"
    return 0
  fi
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -x "${CLAUDE_PLUGIN_ROOT}/bin/mcp-call" ]]; then
    echo "${CLAUDE_PLUGIN_ROOT}/bin/mcp-call"
    return 0
  fi
  return 1
}

agent_brain_mcp_call() {
  local tool="$1"
  local args="${2:-{}}"
  local bin
  if ! bin="$(agent_brain_resolve_mcp_call)"; then
    echo "agent-brain: mcp-call not found; run: go build -o plugins/claude-code/bin/mcp-call ./cmd/mcp-call" >&2
    return 1
  fi
  "$bin" "$tool" "$args"
}

# Claude Code hook output: inject context for UserPromptSubmit / SessionStart
agent_brain_emit_context() {
  local event="$1"
  local block="$2"
  jq -nc --arg ev "$event" --arg ctx "$block" \
    '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}'
}
