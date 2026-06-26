import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { resolveAgentId } from "./config.js";
import type { PluginApi } from "./recall.js";
import { loadLastUserPrompt } from "./session-state.js";

export type AgentEndCtx = {
  sessionKey?: string;
  trigger?: string;
  messages?: Array<{ role?: string; content?: string }>;
};

export function createCaptureHook(api: PluginApi, cfg: AgentBrainPluginConfig) {
  return async (ctx: AgentEndCtx) => {
    if (ctx.trigger === "memory") return {};
    if (ctx.sessionKey?.includes(":memory-capture:")) return {};

    const lastPrompt = await loadLastUserPrompt(ctx.sessionKey).catch(() => "");
    if (!lastPrompt.trim()) return {};

    const agentId = resolveAgentId(cfg, ctx.sessionKey);
    const eventId = `turn-${new Date().toISOString().replace(/[:.]/g, "-")}-${Date.now() % 100000}`;

    const observations = (ctx.messages ?? [])
      .filter((m) => m.role === "assistant" && m.content?.trim())
      .slice(-2)
      .map((m) => ({
        type: "agent_response",
        value: (m.content ?? "").slice(0, 1000),
        confidence: 0.8,
      }));

    try {
      await callMcpTool(
        cfg,
        api.rootDir,
        "memory_write",
        {
          event_id: eventId,
          type: "conversation",
          trigger: {
            type: "input",
            content: lastPrompt.slice(0, 500),
          },
          participants: [
            { id: "user", type: "self" },
            { id: agentId, type: "agent" },
          ],
          observations,
          confidence: 0.8,
        },
        ctx.sessionKey,
      );
    } catch (err) {
      api.logger.warn(`agent-brain: memory_write failed: ${String(err)}`);
    }

    return {};
  };
}
