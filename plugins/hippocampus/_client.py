"""Minimal MCP StreamableHTTP client for agent-brain."""
from __future__ import annotations

import json
import time
import logging
from typing import Any, Optional

logger = logging.getLogger(__name__)

_TOOL_CALL_METHOD = "tools/call"
_MCP_PROTOCOL_VERSION = "2024-11-05"


class AgentBrainClient:
    """Thin HTTP wrapper around the agent-brain MCP endpoint.

    Follows StreamableHTTP transport: POST JSON-RPC 2.0 to {url}.
    Performs the MCP initialize handshake on first use to obtain a
    session ID, then includes Mcp-Session-Id on all subsequent calls.
    """

    def __init__(self, url: str, api_key: str, agent_id: str, timeout: float = 15.0) -> None:
        self._url = url.rstrip("/")
        self._api_key = api_key
        self._agent_id = agent_id
        self._timeout = timeout
        self._client = None  # lazy-initialised httpx.Client
        self._session_id: Optional[str] = None

    def _get_client(self):
        if self._client is None:
            try:
                import httpx
            except ImportError:
                raise RuntimeError(
                    "httpx is required for the agent-brain memory plugin. "
                    "Run: pip install httpx"
                )
            self._client = httpx.Client(
                headers={
                    "X-API-Key": self._api_key,
                    "X-Agent-ID": self._agent_id,
                    "Content-Type": "application/json",
                    "Accept": "application/json, text/event-stream",
                },
                timeout=self._timeout,
            )
        return self._client

    def _ensure_session(self) -> None:
        """Perform MCP initialize handshake if we don't have a session yet."""
        if self._session_id:
            return
        client = self._get_client()
        payload = {
            "jsonrpc": "2.0",
            "id": "init-1",
            "method": "initialize",
            "params": {
                "protocolVersion": _MCP_PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "hippocampus", "version": "1.0.0"},
            },
        }
        resp = client.post(self._url, json=payload)
        resp.raise_for_status()
        self._session_id = resp.headers.get("Mcp-Session-Id", "")
        logger.debug("agent-brain session established: %s", self._session_id)

    def call_tool(self, tool_name: str, arguments: dict[str, Any]) -> Any:
        """Call a tool and return the parsed result dict. Raises on error."""
        self._ensure_session()
        payload = {
            "jsonrpc": "2.0",
            "id": f"{tool_name}-{int(time.time() * 1000)}",
            "method": _TOOL_CALL_METHOD,
            "params": {"name": tool_name, "arguments": arguments},
        }
        client = self._get_client()
        headers = {}
        if self._session_id:
            headers["Mcp-Session-Id"] = self._session_id
        try:
            resp = client.post(self._url, json=payload, headers=headers)
            if resp.status_code == 404:
                # Session may have expired — reset and retry once
                self._session_id = None
                self._ensure_session()
                if self._session_id:
                    headers["Mcp-Session-Id"] = self._session_id
                resp = client.post(self._url, json=payload, headers=headers)
            resp.raise_for_status()
        except Exception as exc:
            logger.warning("agent-brain %s request failed: %s", tool_name, exc)
            raise

        content_type = resp.headers.get("content-type", "")
        if "text/event-stream" in content_type:
            return self._parse_sse(resp.text, tool_name)

        data = resp.json()
        if "error" in data:
            raise RuntimeError(f"agent-brain error: {data['error']}")
        return self._extract_result(data.get("result", {}))

    def call_tool_safe(self, tool_name: str, arguments: dict[str, Any]) -> str:
        """Like call_tool but returns a JSON string and never raises."""
        try:
            result = self.call_tool(tool_name, arguments)
            return json.dumps(result) if not isinstance(result, str) else result
        except Exception as exc:
            return json.dumps({"error": str(exc), "success": False})

    def _extract_result(self, result: Any) -> Any:
        """Pull the text payload out of MCP content blocks."""
        if isinstance(result, dict):
            content = result.get("content", [])
            if isinstance(content, list) and content:
                texts = [
                    block.get("text", "")
                    for block in content
                    if isinstance(block, dict) and block.get("type") == "text"
                ]
                combined = "\n".join(t for t in texts if t)
                try:
                    return json.loads(combined)
                except (json.JSONDecodeError, ValueError):
                    return combined
        return result

    def _parse_sse(self, text: str, tool_name: str) -> Any:
        """Parse Server-Sent Events response, returning the last result."""
        result = None
        for line in text.splitlines():
            if not line.startswith("data:"):
                continue
            raw = line[len("data:"):].strip()
            if raw in ("", "[DONE]"):
                continue
            try:
                msg = json.loads(raw)
                if "result" in msg:
                    result = self._extract_result(msg["result"])
                elif "error" in msg:
                    raise RuntimeError(f"agent-brain SSE error: {msg['error']}")
            except (json.JSONDecodeError, ValueError):
                continue
        return result

    def close(self) -> None:
        if self._client is not None:
            try:
                self._client.close()
            except Exception:
                pass
            self._client = None
