# Agent Brain — OpenClaw Plugin

Native [OpenClaw](https://openclaw.ai) plugin: **hosted agent-brain** over HTTP/SSE, with typed lifecycle hooks (`before_prompt_build`, `agent_end`).

No Postgres or local `go run` in the plugin — only your hosted MCP endpoint + optional `mcp-call` binary.

## OpenClaw conventions

| Piece | Location |
|-------|----------|
| Manifest | `openclaw.plugin.json` (`kind: "memory"`) |
| Entry | `index.ts` via `package.json` → `openclaw.extensions` |
| Hooks | `api.on("before_prompt_build")`, `api.on("agent_end")` |
| Recall injection | `prependContext` (untrusted XML block) |
| Memory slot | `plugins.slots.memory: "agent-brain"` |

Instructions for the agent live in hosted memory + MCP tools — not a root `CLAUDE.md` in the plugin (per OpenClaw plugin guidance).

## Install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/openclaw/install.sh | bash -s -- \
  --url https://agent-memory.nighthawklabs.org/sse \
  --agent-id openclaw-you \
  --api-key YOUR_KEY \
  --restart
```

From a cloned repo:

```bash
./plugins/openclaw/install.sh --url https://memory.example.com/sse --agent-id openclaw-you --api-key YOUR_KEY --restart
```

The script downloads `mcp-call`, links the plugin with OpenClaw, and merges `~/.openclaw/openclaw.json` (requires `jq`).

## Manual install

```bash
./scripts/fetch-mcp-call.sh plugins/openclaw/bin/mcp-call
openclaw plugins install --link ./plugins/openclaw
```

Merge `templates/openclaw.jsonc` into `~/.openclaw/openclaw.json` and set env vars:

| Variable | Purpose |
|----------|---------|
| `NIGHTHAWK_MCP_URL` | Hosted SSE URL |
| `NIGHTHAWK_API_KEY` or JWT in config | Auth |
| `NIGHTHAWK_AGENT_ID` | e.g. `openclaw-alice` or `openclaw-alice-fitness-coach` |

Restart gateway:

```bash
openclaw gateway restart
openclaw plugins inspect agent-brain --runtime --json
```

## Agent id conventions

| Style | Example |
|-------|---------|
| Fixed (7 specialist agents) | `openclaw-fitness-coach`, `openclaw-finance-manager` |
| Derived from session | `agentPrefix` + session key slug (config default `openclaw`) |
| User-global | `openclaw-alice` |

Register each `agentId` for your user in **Memory Explorer → Settings** (`iam_service_accounts`). Each OpenClaw binding needs its own registered agent id under your tenant.

## MCP tools (explicit)

Add the `mcp` block in `openclaw.json` (see template) so agents can call `memory_search`, `memory_write`, skills, intentions, etc. Hooks handle automatic recall/capture; MCP handles explicit operations.

## Plugin config

| Key | Default | Description |
|-----|---------|-------------|
| `url` | (required) | Hosted SSE endpoint |
| `apiKey` / `jwt` | — | Auth |
| `agentId` | — | Fixed agent id |
| `agentPrefix` | `openclaw` | Used when deriving id from `sessionKey` |
| `autoRecall` | `true` | `before_prompt_build` |
| `autoCapture` | `true` | `agent_end` |
| `recallLimit` | `8` | Max memories injected |
| `recallMinPromptLength` | `12` | Skip "hi", "ok", etc. |
| `mcpCallPath` | `<plugin>/bin/mcp-call` | Override CLI path |

## Tests

```bash
cd plugins/openclaw && npm test
```

## Docs

- [Runbook](../../docs/runbooks/openclaw-plugin.md)
- [Spec](../../docs/superpowers/specs/2026-06-04-openclaw-plugin-design.md)
