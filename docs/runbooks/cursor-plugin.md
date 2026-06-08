# Cursor plugin runbook

Client-only integration: hosted agent-brain **SSE MCP** + Cursor **hooks**. No database or server process on the developer machine.

**Spec:** [2026-06-04-cursor-plugin-design.md](../superpowers/specs/2026-06-04-cursor-plugin-design.md)  
**Plan:** [2026-06-04-cursor-plugin.md](../superpowers/plans/2026-06-04-cursor-plugin.md)

## Prerequisites

- Hosted `agent-brain` with `TRANSPORT=sse`
- `NIGHTHAWK_AGENT_ID` registered for your user in Postgres IAM (Memory Explorer → Settings, or `/v1/explorer/settings/agents`)
- API key (`API_KEYS`) or JWT (`JWT_SECRET`, claim `sub` = user id)
- `jq` on PATH
- Built CLI: `./scripts/fetch-mcp-call.sh plugins/cursor/bin/mcp-call` (or `go build` fallback)

## Install

**Web UI (Memory Explorer):** open **Get started** and **Settings** in agent-web to register agents, create API keys/JWT, and copy install commands for `https://agent-memory.nighthawklabs.org/mcp`.

**Cursor `/add-plugin`:** when `agent-brain` is published to the Cursor marketplace, run `/add-plugin agent-brain` in chat; otherwise use `install.sh` below.

**Global** (`~/.cursor/`) — recommended:

```bash
curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/cursor/install.sh | bash -s -- \
  --global \
  --url https://agent-memory.nighthawklabs.org/mcp \
  --agent-id cursor-you \
  --api-key YOUR_KEY
```

Manual copy (without install.sh):

```bash
cp plugins/cursor/templates/mcp.json ~/.cursor/mcp.json
cp plugins/cursor/templates/hooks.json ~/.cursor/hooks.json
cp -r plugins/cursor/hooks ~/.cursor/hooks
./scripts/fetch-mcp-call.sh ~/.cursor/bin/mcp-call
chmod +x ~/.cursor/hooks/*.sh ~/.cursor/hooks/lib/*.sh ~/.cursor/bin/mcp-call
```

**Project** (repo `.cursor/`): same paths under the repository root.

### Environment

| Variable | Example |
|----------|---------|
| `NIGHTHAWK_MCP_URL` | `https://memory.example.com/sse` |
| `NIGHTHAWK_API_KEY` | from operator |
| `NIGHTHAWK_AGENT_ID` | `cursor-alice` (global) or `cursor-alice-agent-brain` (project) |
| `NIGHTHAWK_JWT` | alternative to API key |
| `NIGHTHAWK_RECALL_LIMIT` | optional, default 8 |
| `NIGHTHAWK_RECALL_MAX` | optional, default 8 |

Use TLS in production. Do not commit secrets in `mcp.json`.

### Register your agent (hosted IAM)

Per-user agents live in Postgres (`iam_service_accounts`), not a JSON file.

1. Open **Memory Explorer → Settings** (or call `PUT /v1/explorer/settings/agents` with your API key/JWT).
2. Register your `NIGHTHAWK_AGENT_ID` (e.g. `cursor-alice`) with role `assistant` and `max_signal_tier: 1`.

New users get default domain ACL `* → *` in `iam_domain_acl`. Restrict domains later via API if needed.

## Update

Syncs hooks and skills to `~/.cursor/` without touching credentials or binaries. No restart needed for skills; restart Cursor for hook changes.

```bash
# Remote
curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/cursor/update.sh | bash

# Local checkout
./plugins/cursor/update.sh
```

## Smoke test

```bash
export NIGHTHAWK_MCP_URL=https://memory.example.com/sse
export NIGHTHAWK_API_KEY=your-key
export NIGHTHAWK_AGENT_ID=cursor-alice
export NIGHTHAWK_SESSION_ID=smoke-1

plugins/cursor/bin/mcp-call memory_search '{"query":"preferences","limit":3}'
```

JWT:

```bash
go run ./scripts/mint-jwt.go   # if present; or use your IdP
export NIGHTHAWK_JWT=...
unset NIGHTHAWK_API_KEY
```

## Hook behavior

| Event | Action |
|-------|--------|
| `sessionStart` | Persist `NIGHTHAWK_SESSION_ID` under `.cursor/state` |
| `beforeSubmitPrompt` | `memory_search` → `additional_context` injection |
| `afterAgentResponse` / `stop` | Conservative `memory_write` for stated preferences |

Failures **fail open** (no block); errors go to stderr / Hooks output channel.

### Context injection field

Recall hook returns:

```json
{"additional_context": "## Memory context (agent-brain)\n- ..."}
```

If injection does not appear after a Cursor upgrade, check Hooks output channel and Cursor release notes for `beforeSubmitPrompt` response schema changes.

## Local hook tests (no server)

```bash
plugins/cursor/tests/run-hook-tests.sh
```

## Troubleshooting

| Symptom | Check |
|---------|--------|
| 401 from `mcp-call` | API key mapping, JWT `sub`, `AUTH_REQUIRED` |
| No memory injected | Hooks enabled; `NIGHTHAWK_MCP_URL`; recall timeout; empty search |
| Writes rejected | Agent registered in Settings? `max_signal_tier` / domain ACL for your user |
| `mcp-call not found` | Build binary; path `~/.cursor/bin/mcp-call` or `.cursor/bin/mcp-call` |

## Repo dev vs distributable plugin

Contributors may use repo `.cursor/mcp.json` with **local stdio** (`go run ./cmd/server`) for backend development. End users installing the plugin should use **hosted SSE only** (`plugins/cursor/templates/mcp.json`).
