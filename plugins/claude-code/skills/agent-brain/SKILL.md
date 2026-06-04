---
name: agent-brain
description: Use when the task needs durable user facts, cross-session preferences, or explicit memory_search/memory_write via agent-brain MCP. Hooks already inject recall on each prompt; use tools for targeted lookup, contradictions, skills, and intentions.
---

# Agent brain (Claude Code)

Unified memory is provided by the **agent-brain** MCP server (hosted). This plugin wires **automatic recall** (`UserPromptSubmit` hook) and **indexing** (`Stop` hook).

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

- `agent_id` — your `NIGHTHAWK_AGENT_ID` (e.g. `claude-alice` or `claude-alice-myrepo`)
- `session_id` — current session (hooks set `NIGHTHAWK_SESSION_ID`)
- `signal_type` — `user-stated`, `inferred`, `behavioral`, `tool-output`, `cron`, or `canonical`
- `memory_type` — matching type (`stated_fact`, `inferred_fact`, etc.)

Prefer `user-stated` only when the user explicitly said the fact. Use `inferred` for careful extractions. Cursor-tier agents typically cannot write `canonical` (server policy).

## Compaction

Memory context from hooks is re-fetched each turn. After compaction, rely on hooks + MCP search again — do not assume facts only exist in the visible transcript.

## Install / env

See `plugins/claude-code/README.md`. Required: `NIGHTHAWK_MCP_URL`, `NIGHTHAWK_AGENT_ID`, and `NIGHTHAWK_API_KEY` or `NIGHTHAWK_JWT`.
