# Cursor Memory Protocol

After EVERY response, run this check before your next action.

## WRITE TRIGGERS — call memory_write NOW if any occurred:
- User stated a preference: "I prefer X", "I always Y", "I never Z", "I want X"
- User made a correction: "no", "not that", "actually X", "wrong", "instead"
- User stated a constraint: "in this project/repo", "we always", "we don't use", "our convention is"
- User revealed a fact: name, role, tech stack, goal, team, deadline
- Architectural decision confirmed: "let's go with X", "we decided", "use X approach"

## WRITE PROTOCOL:
1. Call memory_get(subject="<label>") first — skip write if fact already exists unchanged
2. Call memory_write:
   - signal_type: "user-stated" (explicit) | "inferred" (observed pattern, conf 0.65–0.75)
   - memory_type: "stated_fact" | "inferred_fact" | "structured_artifact"
   - subject: short canonical label — "user.coding.style", "project.stack", "user.goal.X"
   - content: self-contained fact sentence, not a raw quote
   - confidence: 0.95 user-stated, 0.70 inferred

## INTENTIONS — handle immediately, not at session end:
- "remind me", "later", "I'll do X tomorrow", "follow up on X" → set_intention(content, topic)
- Deferred task completed this session → complete_intention(intention_id)

## PROJECT SKILLS — when user codifies a reusable rule:
- "always use X pattern in this repo", project convention → ingest_skill(name, body, description)
- Use for agent instructions, NOT preference facts (those go to memory_write)

## DO NOT WRITE:
- Routine code edits, file reads, implementation steps
- "ok", "thanks", "looks good", boilerplate confirmations
- Facts already in recalled context that have not changed
