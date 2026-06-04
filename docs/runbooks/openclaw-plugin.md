# OpenClaw plugin runbook

Native plugin at `plugins/openclaw/`. Connects to **hosted** agent-brain (SSE). Implements `before_prompt_build` and `agent_end` (see agent-brain memory service design in the private server repo).

## Prerequisites

- OpenClaw >= 2026.3.0
- Hosted agent-brain (`TRANSPORT=sse`)
- Each `agentId` registered in Postgres IAM (Memory Explorer → **Settings**, table `iam_service_accounts`)
- Built `plugins/openclaw/bin/mcp-call`

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/realnighthawk/agent-plugins/main/plugins/openclaw/install.sh | bash -s -- \
  --url https://agent-memory.nighthawklabs.org/sse \
  --agent-id openclaw-alice \
  --api-key YOUR_KEY \
  --restart
```

Requires `jq` for config merge. Manual merge reference (`plugins/openclaw/templates/openclaw.jsonc`):

```jsonc
{
  "plugins": {
    "slots": { "memory": "agent-brain" },
    "entries": {
      "agent-brain": {
        "enabled": true,
        "config": {
          "url": "https://memory.example.com/sse",
          "apiKey": "${NIGHTHAWK_API_KEY}",
          "agentId": "openclaw-fitness-coach",
          "autoRecall": true,
          "autoCapture": true
        }
      }
    }
  },
  "mcp": {
    "agent-brain": {
      "type": "streamable-http",
      "url": "https://memory.example.com/sse",
      "headers": {
        "X-API-Key": "${NIGHTHAWK_API_KEY}",
        "X-Agent-ID": "openclaw-fitness-coach"
      }
    }
  }
}
```

```bash
openclaw gateway restart
openclaw plugins inspect agent-brain --runtime --json
```

## Multi-agent (superclaw)

Use one plugin install; set **per-binding** `agentId` via separate OpenClaw agent configs or derived `sessionKey` + `agentPrefix`. Register each specialist in **Settings** (e.g. `openclaw-fitness-coach`, `openclaw-finance-manager`).

## Verify

Gateway logs should include `agent-brain: registered hooks: before_prompt_build, agent_end`.

Send a message with a preference statement; on stop, confirm write via explorer or `mcp-call memory_search`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Hooks not registered | `plugins.entries.agent-brain.enabled`; memory slot; gateway restart |
| Recall empty | URL/auth; `recallMinPromptLength`; agent registered in Settings |
| mcp-call ENOENT | Build binary; set `mcpCallPath` |
| MCP tools missing | Add `mcp` block in openclaw.json (separate from plugin) |

Only one `plugins.slots.memory` plugin active at a time — disable `memory-core` when enabling agent-brain.
