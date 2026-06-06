import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { resolveAgentId } from "./config.js";
import type { PluginApi } from "./recall.js";
import { loadAndClearTriggeredIntentionIds } from "./session-state.js";

export type AgentEndCtx = {
  sessionKey?: string;
  trigger?: string;
  messages?: Array<{ role?: string; content?: string }>;
};

export function createCaptureHook(api: PluginApi, cfg: AgentBrainPluginConfig) {
  return async (ctx: AgentEndCtx) => {
    if (ctx.trigger === "memory") return {};
    if (ctx.sessionKey?.includes(":memory-capture:")) return {};

    const agentId = resolveAgentId(cfg, ctx.sessionKey);

    // Complete intentions that were triggered (and acted on) during this session.
    const triggeredIds = await loadAndClearTriggeredIntentionIds(ctx.sessionKey);
    for (const id of triggeredIds) {
      try {
        await callMcpTool(
          cfg,
          api.rootDir,
          "complete_intention",
          { agent_id: agentId, intention_id: id },
          ctx.sessionKey,
        );
      } catch (err) {
        api.logger.warn(`agent-brain: complete_intention failed: ${String(err)}`);
      }
    }

    return {};
  };
}
