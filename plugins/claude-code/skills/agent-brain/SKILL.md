---
name: agent-brain
description: Use when the task needs durable user facts, cross-session preferences, or explicit memory_search/memory_write via agent-brain MCP. Hooks already inject recall on each prompt; use tools for targeted lookup, contradictions, skills, and intentions.
---

# Agent brain (Claude Code)

Unified memory is **only** in the hosted **agent-brain** MCP server. This plugin wires automatic recall (`UserPromptSubmit`) and indexing (`Stop`).

## Hard rules

1. **Never** save memory to Claude project files (`~/.claude/projects/.../memory/`), local markdown, or any filesystem fallback.
2. **Never** invent an `agent_id` (email, username, etc.). The server uses `X-Agent-ID` from plugin auth (`NIGHTHAWK_AGENT_ID`, e.g. `claude-code-mac`). Omit `agent_id` in tool args when possible.
3. If `memory_write` fails, **report the error** to the user. Do not silently store elsewhere.
4. Do **not** use `memory.search`, `memory.write`, or `memory.close_session` — those are not agent-brain tools.

## When to use MCP tools directly

| Situation | Tool |
|-----------|------|
| Targeted lookup by subject | `memory_get` |
| Deep search with explain | `memory_search` with `include_explain` |
| Explicit durable fact | `memory_write` with correct `signal_type` |
| Contradictions | `list_contradictions`, `resolve_contradiction` |
| Reusable procedures | `retrieve_skills_for_context`, `invoke_skill` |
| Deferred reminders | `set_intention`, `check_intentions` |

Hooks already run `memory_search` before each user prompt. Do not repeat the same broad search unless the user asks or new domain context appeared.

## Write provenance

Every `memory_write` must include:

- `session_id` — current Claude session id
- `signal_type` — `user-stated`, `inferred`, `behavioral`, `tool-output`, `cron`, or `canonical`
- `memory_type` — matching type (`stated_fact`, `inferred_fact`, etc.)
- `content`, `subject` — self-contained fact text and short label

Use `user-stated` when the user explicitly said the fact. If the server rejects `user-stated` (agent policy), tell the user to raise `max_signal_tier` in Memory Explorer → Settings — do not fall back to local storage.

## Compaction

Memory context from hooks is re-fetched each turn. After compaction, rely on hooks + MCP search again.

## Install / env

See `plugins/claude-code/README.md`. Required: `NIGHTHAWK_MCP_URL`, `NIGHTHAWK_AGENT_ID`, and `NIGHTHAWK_API_KEY` or `NIGHTHAWK_JWT` in `~/.claude/settings.json` env or sourced from `~/.config/agent-brain/claude.env`.
