"""agent-brain memory provider for Hermes Agent.

Replaces the built-in OpenViking memory tool with agent-brain's episodic
memory system. Activate by setting memory.provider: agent-brain in config.yaml.

Auto-prefetches relevant context via memory_recall before each turn.
Auto-saves conversation turns via memory_write in the background.
Exposes memory_write, memory_search, memory_recall, and memory_graph
as explicit tools the agent can call.
"""
from __future__ import annotations

import json
import logging
import os
import threading
import time
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Tool schemas (OpenAI function-calling format)
# ---------------------------------------------------------------------------

_MEMORY_WRITE_SCHEMA: Dict[str, Any] = {
    "name": "memory_write",
    "description": (
        "Write an episodic event to long-term memory. Use to save preferences, "
        "decisions, facts, or anything the user wants remembered across sessions. "
        "Call memory_search first to discover existing entity IDs before writing."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "event_id": {
                "type": "string",
                "description": "Unique idempotency key for this event (re-submitting same id is a no-op).",
            },
            "type": {
                "type": "string",
                "description": 'Event category e.g. "preference", "decision", "fact", "conversation".',
            },
            "trigger": {
                "type": "object",
                "description": 'What triggered this event. Shape: {"type": "input"|"agent", "content": "..."}',
            },
            "observations": {
                "type": "array",
                "description": (
                    'Extracted insights. Each item: {"type": "preference_stated", '
                    '"value": "...", "confidence": 0.9}'
                ),
            },
            "entities": {
                "type": "array",
                "description": (
                    'Persistent objects. Each item: {"id": "local-alias", "type": "person|project|...", '
                    '"name": "Human Name", "confidence": 0.9}'
                ),
            },
            "facts": {
                "type": "array",
                "description": (
                    'SPO triples. Each item: {"subject": "entity-id", "predicate": "prefers", '
                    '"object": "entity-id-or-literal", "confidence": 0.95}'
                ),
            },
            "confidence": {
                "type": "number",
                "description": "Overall event confidence 0-1. Default 0.8.",
            },
        },
        "required": ["event_id", "trigger"],
    },
}

_MEMORY_SEARCH_SCHEMA: Dict[str, Any] = {
    "name": "memory_search",
    "description": (
        "Search existing entities, predicates, and entity types by natural language. "
        "Call this before memory_write to discover canonical IDs and avoid duplicates."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": 'Natural language search e.g. "food preference", "visited doctor"',
            },
            "kinds": {
                "type": "string",
                "description": 'Comma-separated: "entities", "predicates", "entity_types". Omit for all.',
            },
            "limit": {
                "type": "integer",
                "description": "Max results per kind (default 10, max 25).",
            },
        },
        "required": ["query"],
    },
}

_MEMORY_RECALL_SCHEMA: Dict[str, Any] = {
    "name": "memory_recall",
    "description": (
        "Semantic recall over episodic memory. Returns activation-scored memory units "
        "relevant to the query. Use to retrieve what has been remembered about a topic."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": "Natural language recall query.",
            },
            "limit": {
                "type": "integer",
                "description": "Max memory units to return (default 10).",
            },
        },
        "required": ["query"],
    },
}

_MEMORY_GRAPH_SCHEMA: Dict[str, Any] = {
    "name": "memory_graph",
    "description": (
        "N-hop knowledge graph snapshot from an entity seed. Returns nodes and weighted "
        "edges. Use to explore what is connected to a known entity."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "subject": {
                "type": "string",
                "description": 'Entity canonical name e.g. "person:alice".',
            },
            "mode": {
                "type": "string",
                "description": '"topics" (default) — relationship map; "facts" — SPO triple view.',
            },
        },
        "required": ["subject"],
    },
}


# ---------------------------------------------------------------------------
# MemoryProvider implementation
# ---------------------------------------------------------------------------

class AgentBrainMemoryProvider:
    """agent-brain memory backend for Hermes."""

    @property
    def name(self) -> str:
        return "hippocampus"

    def is_available(self) -> bool:
        return bool(
            os.environ.get("NIGHTHAWK_MCP_URL", "").strip()
            and os.environ.get("NIGHTHAWK_API_KEY", "").strip()
        )

    def initialize(self, session_id: str, **kwargs) -> None:
        from ._client import AgentBrainClient

        self._session_id = session_id
        self._agent_id = (
            os.environ.get("NIGHTHAWK_AGENT_ID", "").strip() or "hermes"
        )
        self._mcp_url = os.environ.get("NIGHTHAWK_MCP_URL", "").strip()
        self._api_key = os.environ.get("NIGHTHAWK_API_KEY", "").strip()

        self._client = AgentBrainClient(
            url=self._mcp_url,
            api_key=self._api_key,
            agent_id=self._agent_id,
        )

        # Pre-fetched recall text for the current turn
        self._prefetch_lock = threading.Lock()
        self._prefetch_result: str = ""
        self._prefetch_thread: Optional[threading.Thread] = None

        logger.info("agent-brain memory provider initialised (agent_id=%s)", self._agent_id)

    def system_prompt_block(self) -> str:
        return (
            "## Persistent Memory\n"
            f"Active via agent-brain (agent_id: {self._agent_id}). "
            "Use `memory_write` to save preferences, facts, or decisions. "
            "Use `memory_search` to find existing entities before writing. "
            "Use `memory_recall` to retrieve relevant past context. "
            "Auto-recall runs before each turn — check the Memory section above if present."
        )

    # -- Prefetch (background recall before each turn) -----------------------

    def queue_prefetch(self, query: str, *, session_id: str = "") -> None:
        """Start background recall so the result is ready when prefetch() is called."""
        def _run() -> None:
            try:
                result = self._client.call_tool("memory_recall", {"query": query, "limit": 6})
                text = self._format_recall(result)
                with self._prefetch_lock:
                    self._prefetch_result = text
            except Exception as exc:
                logger.debug("agent-brain prefetch failed: %s", exc)
                with self._prefetch_lock:
                    self._prefetch_result = ""

        with self._prefetch_lock:
            self._prefetch_result = ""

        t = threading.Thread(target=_run, daemon=True)
        t.start()
        with self._prefetch_lock:
            self._prefetch_thread = t

    def prefetch(self, query: str, *, session_id: str = "") -> str:
        """Return recalled context to prepend to the turn."""
        if self._prefetch_thread and self._prefetch_thread.is_alive():
            self._prefetch_thread.join(timeout=5.0)
        with self._prefetch_lock:
            result = self._prefetch_result
            self._prefetch_result = ""
        return result

    def _format_recall(self, raw: Any) -> str:
        """Format recall result into a concise context block."""
        if not raw:
            return ""
        try:
            data = json.loads(raw) if isinstance(raw, str) else raw
        except (json.JSONDecodeError, ValueError):
            return ""

        emus = data.get("emus", []) if isinstance(data, dict) else []
        if not emus:
            return ""

        lines = ["## Memory (agent-brain recall)"]
        for emu in emus[:6]:
            obs = emu.get("observations") or emu.get("trigger_content") or ""
            if isinstance(obs, list):
                obs = "; ".join(
                    o.get("value", "") for o in obs if isinstance(o, dict)
                )
            if obs:
                score = emu.get("activation_score", "")
                score_str = f" [{score:.2f}]" if isinstance(score, float) else ""
                lines.append(f"- {obs}{score_str}")
        return "\n".join(lines) if len(lines) > 1 else ""

    # -- Sync turn (background write after each turn) ------------------------

    def sync_turn(
        self,
        user_content: str,
        assistant_content: str,
        *,
        session_id: str = "",
        messages: Optional[List[Dict[str, Any]]] = None,
    ) -> None:
        """Write the completed turn to agent-brain in the background."""
        sid = session_id or self._session_id
        agent_id = self._agent_id

        def _write() -> None:
            try:
                event_id = f"turn-{sid}-{int(time.time() * 1000)}"
                self._client.call_tool("memory_write", {
                    "event_id": event_id,
                    "type": "conversation",
                    "trigger": {
                        "type": "input",
                        "content": user_content[:500],
                    },
                    "participants": [
                        {"id": "user", "type": "self"},
                        {"id": agent_id, "type": "agent"},
                    ],
                    "observations": [
                        {
                            "type": "agent_response",
                            "value": assistant_content[:1000],
                            "confidence": 0.8,
                        }
                    ],
                    "confidence": 0.8,
                })
            except Exception as exc:
                logger.debug("agent-brain sync_turn write failed: %s", exc)

        threading.Thread(target=_write, daemon=True).start()

    # -- Explicit tools the agent can call -----------------------------------

    def get_tool_schemas(self) -> List[Dict[str, Any]]:
        return [
            _MEMORY_WRITE_SCHEMA,
            _MEMORY_SEARCH_SCHEMA,
            _MEMORY_RECALL_SCHEMA,
            _MEMORY_GRAPH_SCHEMA,
        ]

    def handle_tool_call(self, tool_name: str, args: Dict[str, Any], **kwargs) -> str:
        # memory_graph needs agent_id injected
        if tool_name == "memory_graph":
            args = {"agent_id": self._agent_id, **args}
        return self._client.call_tool_safe(tool_name, args)

    def shutdown(self) -> None:
        if hasattr(self, "_client"):
            self._client.close()


# ---------------------------------------------------------------------------
# Plugin registration
# ---------------------------------------------------------------------------

def register(ctx) -> None:
    ctx.register_memory_provider(AgentBrainMemoryProvider())
