# Agent Brain — Cursor Plugin

Client-only integration for agent-brain: **hosted MCP (SSE)** plus **Cursor hooks** for per-turn recall and indexing.

No database, Docker, or `go run` in this package.

## Prerequisites

- Hosted agent-brain SSE endpoint (e.g. `https://memory.example.com/sse`)
- API key or JWT registered on the server
- Agent id registered for your user in Postgres (`iam_service_accounts` via Memory Explorer **Settings**)
- `jq` on PATH

## Install via Cursor `/add-plugin` (when published)

In Cursor chat:

```
/add-plugin agent-brain
```

Then set credentials in `~/.cursor/agent-brain.env` (or run `install.sh` below). The plugin manifest lives in `plugins/cursor/.cursor-plugin/plugin.json`. Until the plugin is listed in the Cursor marketplace, use the install script or copy templates manually.

## Install (recommended)

From the agent-brain repository root:

```bash
# All Cursor workspaces (global ~/.cursor/)
./plugins/cursor/install.sh --global \
  --url https://agent-memory.nighthawklabs.org/mcp \
  --agent-id cursor-agent \
  --api-key YOUR_API_KEY

# Or JWT instead of API key:
./plugins/cursor/install.sh --global \
  --url https://agent-memory.nighthawklabs.org/mcp \
  --agent-id cursor-agent \
  --jwt "$(go run ./scripts/mint-jwt.go -sub YOUR_USER_ID -secret YOUR_JWT_SECRET)"
```

Remote one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/cursor/install.sh | bash -s -- \
  --global --url https://agent-memory.nighthawklabs.org/mcp --agent-id cursor-you --api-key YOUR_KEY
```

The script downloads `mcp-call`, copies hooks, writes `~/.cursor/agent-brain.env`, merges `agent-brain` into `~/.cursor/mcp.json`, and installs `~/.cursor/hooks.json`.

Restart Cursor. Enable **Hooks** in Settings and check the Hooks output channel.

### Manual install

See [docs/runbooks/cursor-plugin.md](../../docs/runbooks/cursor-plugin.md) for copy-by-hand steps.

## Agent id conventions

| Install | Suggested `NIGHTHAWK_AGENT_ID` |
|---------|--------------------------------|
| Global | `cursor-<user>` |
| Project | `cursor-<user>-<project>` |

Per-conversation provenance uses **`X-Session-ID`** (set by `session-start` hook), not the agent id.

## Tests

```bash
plugins/cursor/tests/run-hook-tests.sh
```

## Docs

- Runbook: [docs/runbooks/cursor-plugin.md](../../docs/runbooks/cursor-plugin.md)
- Spec: [docs/superpowers/specs/2026-06-04-cursor-plugin-design.md](../../docs/superpowers/specs/2026-06-04-cursor-plugin-design.md)
- Plan: [docs/superpowers/plans/2026-06-04-cursor-plugin.md](../../docs/superpowers/plans/2026-06-04-cursor-plugin.md)
