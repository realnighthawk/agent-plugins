# Agent Brain — Cursor Plugin

Client-only integration for agent-brain: **hosted MCP (SSE)** plus **Cursor hooks** for per-turn recall and indexing.

No database, Docker, or `go run` in this package.

## Plugin layout

```
plugins/cursor/
├── .cursor-plugin/plugin.json   # manifest
├── hooks/                       # sessionStart, recall, index hook commands
├── skills/
│   ├── agent-brain/SKILL.md     # memory write protocol (injected at session start)
│   └── replay-memory/SKILL.md   # historical transcript → memory extraction
├── scripts/
│   └── extract_conversations.py # Phase 1 replay: ~/.cursor/projects → ~/.cursor/replay
└── templates/                   # mcp.json, hooks.json templates
```

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
./plugins/cursor/install.sh --scope global \
  --url https://agent-memory.nighthawklabs.org/mcp \
  --agent-id cursor-agent \
  --api-key YOUR_API_KEY

# Or JWT instead of API key:
./plugins/cursor/install.sh --scope global \
  --url https://agent-memory.nighthawklabs.org/mcp \
  --agent-id cursor-agent \
  --jwt "$(go run ./scripts/mint-jwt.go -sub YOUR_USER_ID -secret YOUR_JWT_SECRET)"

# Project-scoped install (./.cursor/)
./plugins/cursor/install.sh --scope project --api-key YOUR_API_KEY
```

`--global` and `--project` are aliases for `--scope global` and `--scope project`.

Remote one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/cursor/install.sh | bash -s -- \
  --scope global --url https://agent-memory.nighthawklabs.org/mcp --agent-id cursor-you --api-key YOUR_KEY
```

The script removes any existing Agent Brain install, builds `mcp-call`, copies hooks and **local** bundled skills (`agent-brain`, `replay-memory`), writes `agent-brain.env`, merges `agent-brain` into `mcp.json`, and installs `hooks.json`.

## Update

Reinstall in place (credentials loaded from `agent-brain.env` if omitted):

```bash
./plugins/cursor/update.sh --scope global
```

Bundled plugin skills are **not** uploaded to agent-brain — `session-start` reads them from disk. After editing skills in the repo, run `./scripts/sync-agent-brain-skills.sh` then `plugins/cursor/update.sh`.

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
