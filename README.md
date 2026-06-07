# agent-plugins

Public client plugins for [agent-brain](https://github.com/realnighthawk/agent-brain) (hosted SSE MCP + hooks).

| IDE | Path | Install |
|-----|------|---------|
| Cursor | [plugins/cursor/](plugins/cursor/README.md) | `curl \| bash` — see [runbook](docs/runbooks/cursor-plugin.md) |
| Claude Code | [plugins/claude-code/](plugins/claude-code/README.md) | [plugins/claude-code/install.sh](plugins/claude-code/install.sh) |
| OpenClaw | [plugins/openclaw/](plugins/openclaw/README.md) | [plugins/openclaw/install.sh](plugins/openclaw/install.sh) |

## Quick install (Cursor)

```bash
curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/cursor/install.sh | bash -s -- \
  --global \
  --url https://agent-memory.nighthawklabs.org/mcp \
  --agent-id cursor-you \
  --api-key YOUR_KEY
```

Register `NIGHTHAWK_AGENT_ID` and create an API key in **Memory Explorer → Settings** before installing.

## `mcp-call` CLI

Hooks use a small Go binary (`cmd/mcp-call`). Install scripts download releases from this repo:

```bash
./scripts/fetch-mcp-call.sh plugins/cursor/bin/mcp-call
```

Tag `v*` releases publish `mcp-call-linux-amd64`, `mcp-call-darwin-arm64`, etc. (see [.github/workflows/publish.yml](.github/workflows/publish.yml)).

**First-time publish:** the repo must be **public**, and you must push a `v*` tag so Actions uploads release assets. Checklist: [docs/PUBLISHING.md](docs/PUBLISHING.md).

## Tests

```bash
go test ./cmd/mcp-call/...
plugins/cursor/tests/run-hook-tests.sh
plugins/claude-code/tests/run-hook-tests.sh
cd plugins/openclaw && npm test
```

## Related

- Hosted memory API: private `agent-brain` repo (deploy your own `memory-api`).
- Memory Explorer UI: `agent-web`.
