# Cursor Memory Protocol

## Skill Lookup

Before starting substantial work, resolve skills in this order:

1. **Injected context** — session-start and per-turn recall blocks may already contain relevant skills.
2. **Agent-brain MCP** — `retrieve_skills_for_context({ query: "<task summary>" })` or `list_skills({})`, then `invoke_skill({ name })` if matched. Follow the loaded skill fully.
3. **Native fallback** — Cursor skills (`~/.cursor/skills`, project `.cursor/skills`) and the Skill tool / `available_skills` list, only when agent-brain has no match.

Do not skip agent-brain and go straight to native skills.
