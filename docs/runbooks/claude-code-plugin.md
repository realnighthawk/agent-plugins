# Claude Code plugin runbook

Official plugin under `plugins/claude-code/`. Connects to **hosted** agent-brain (HTTP MCP → SSE). No local database.

**Spec:** [2026-06-04-claude-code-plugin-design.md](../superpowers/specs/2026-06-04-claude-code-plugin-design.md)

## Prerequisites

- Hosted `TRANSPORT=sse` agent-brain
- `NIGHTHAWK_AGENT_ID` registered in **Settings** (`iam_service_accounts`)
- API key or JWT
- `jq`, built `mcp-call`

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/claude-code/install.sh | bash -s -- \
  --url https://agent-memory.nighthawklabs.org/mcp \
  --agent-id claude-alice \
  --api-key YOUR_KEY
```

Then add to `~/.zshrc` (or merge into `~/.claude/settings.json` → `env` so MCP works when Claude is not launched from a shell):

```bash
source ~/.config/agent-brain/claude.env
```

Or from a clone: `./plugins/claude-code/install.sh` with the same flags.

The installer registers marketplace `agent-plugins` and runs `claude plugin install agent-brain@agent-plugins`.

Export env manually (shell profile or Claude config):

```bash
export NIGHTHAWK_MCP_URL=https://memory.example.com/sse
export NIGHTHAWK_API_KEY=your-key
export NIGHTHAWK_AGENT_ID=claude-alice
```

Verify in Claude Code: `/mcp` lists `agent-brain`. After hook changes: `/reload-plugins`.

## Update

Skips marketplace re-registration (`--skip-plugin-add`) but refreshes `mcp-call` and MCP config. From a local checkout, skill changes are live immediately — run `/reload-plugins` in Claude Code instead.

```bash
# Remote
curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/claude-code/update.sh | bash -s -- \
  --url https://agent-memory.nighthawklabs.org/mcp \
  --agent-id claude-alice \
  --api-key YOUR_KEY

# Local checkout
./plugins/claude-code/update.sh --api-key YOUR_KEY
```

## Agent policy

```json
"claude-alice": {
  "role": "assistant",
  "rank": 50,
  "max_signal_tier": 1
}
```

## Smoke test

```bash
export NIGHTHAWK_MCP_URL=...
export NIGHTHAWK_API_KEY=...
export NIGHTHAWK_AGENT_ID=claude-alice
export NIGHTHAWK_SESSION_ID=smoke-1
plugins/claude-code/bin/mcp-call memory_search '{"query":"test","limit":3}'
```

## Hook troubleshooting

| Issue | Check |
|-------|--------|
| MCP not in `/mcp` | Plugin enabled; env vars set; `/reload-plugins` |
| No recall context | `UserPromptSubmit` hook; Hooks debug log; `NIGHTHAWK_MCP_URL` |
| No writes on stop | User prompt matched heuristic; `last-user-prompt` state file; policy |
| Wrong tenant | API key → user mapping; JWT `sub` |

## Project-only MCP (team)

Alternatively commit a project `.mcp.json` (without the full plugin) per [Claude Code MCP docs](https://code.claude.com/docs/en/mcp). The plugin is preferred when you want hooks + skill bundled.

## Local dev (contributors)

Contributors may run stdio MCP from repo root (`.mcp.json` with `go run ./cmd/server`) — not part of the distributable plugin. End users should use hosted SSE only.
