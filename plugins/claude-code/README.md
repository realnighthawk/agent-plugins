# Agent Brain — Claude Code Plugin

Official [Claude Code plugin](https://code.claude.com/docs/en/plugins-reference) layout: manifest, `.mcp.json`, `hooks/hooks.json`, `scripts/`, and a **skill** (not root `CLAUDE.md` — per Anthropic guidance).

Client-only: connects to **hosted** agent-brain over HTTP/SSE. No Postgres or `go run` in the plugin.

Bundled skills (`agent-brain`, `replay-memory`) are **local-only** — injected at session start from `skills/` on disk, not via `ingest_skill`.

## Plugin layout

```
plugins/claude-code/
├── .claude-plugin/plugin.json   # manifest (required)
├── .mcp.json                    # hosted MCP (http → /sse)
├── hooks/hooks.json             # SessionStart, UserPromptSubmit, Stop
├── scripts/                     # hook commands (${CLAUDE_PLUGIN_ROOT}/scripts/...)
├── skills/agent-brain/     # SKILL.md for /agent-brain:...
├── bin/mcp-call                 # build locally (gitignored)
└── .env.example
```

## Install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/claude-code/install.sh | bash -s -- \
  --url https://agent-memory.nighthawklabs.org/mcp \
  --agent-id claude-you \
  --api-key YOUR_KEY
```

From a cloned repo:

```bash
./plugins/claude-code/install.sh --url https://memory.example.com/sse --agent-id claude-you --api-key YOUR_KEY
```

The script downloads `mcp-call`, registers the `agent-plugins` marketplace, runs `claude plugin install agent-brain@agent-plugins`, and writes `~/.config/agent-brain/claude.env` (source it from your shell profile).

## Manual install

```bash
./scripts/fetch-mcp-call.sh plugins/claude-code/bin/mcp-call
claude plugin marketplace add . --scope user
claude plugin install agent-brain@agent-plugins --scope user
```

Set environment variables in your shell or Claude Code user config (see `.env.example`):

| Variable | Purpose |
|----------|---------|
| `NIGHTHAWK_MCP_URL` | Hosted SSE URL, e.g. `https://memory.example.com/sse` |
| `NIGHTHAWK_API_KEY` or `NIGHTHAWK_JWT` | Auth |
| `NIGHTHAWK_AGENT_ID` | `claude-<user>` or `claude-<user>-<project>` |

Register the agent id in **Memory Explorer → Settings** (`iam_service_accounts` for your user).

After changing hooks or `.mcp.json`, run `/reload-plugins` or restart Claude Code.

## Agent id conventions

| Install style | Example `NIGHTHAWK_AGENT_ID` |
|---------------|------------------------------|
| User-global | `claude-alice` |
| Project-scoped | `claude-alice-agent-brain` |

Session provenance: hooks set `NIGHTHAWK_SESSION_ID` from Claude's `session_id` on `SessionStart`.

## JWT auth

Replace `.mcp.json` headers with `templates/mcp-jwt.json` if you use Bearer tokens instead of API keys.

## Tests

```bash
plugins/claude-code/tests/run-hook-tests.sh
```

## Docs

- Runbook: [docs/runbooks/claude-code-plugin.md](../../docs/runbooks/claude-code-plugin.md)
- Spec: [docs/superpowers/specs/2026-06-04-claude-code-plugin-design.md](../../docs/superpowers/specs/2026-06-04-claude-code-plugin-design.md)
- Cursor sibling: [plugins/cursor/README.md](../cursor/README.md) (same repo)
