import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { resolveAgentId } from "./config.js";
import { indexCandidates } from "./format.js";
import type { PluginApi } from "./recall.js";
import { loadLastUserPrompt, loadAndClearTriggeredIntentionIds } from "./session-state.js";

export type AgentEndCtx = {
  sessionKey?: string;
  trigger?: string;
  messages?: Array<{ role?: string; content?: string }>;
};

function lastExchange(ctx: AgentEndCtx): { user: string; assistant: string } {
  const msgs = ctx.messages ?? [];
  let user = "";
  let assistant = "";
  for (let i = msgs.length - 1; i >= 0; i--) {
    const m = msgs[i];
    const role = (m.role ?? "").toLowerCase();
    const text = typeof m.content === "string" ? m.content : "";
    if (!assistant && role === "assistant" && text) assistant = text;
    if (!user && role === "user" && text) user = text;
    if (user && assistant) break;
  }
  return { user, assistant };
}

export function createCaptureHook(api: PluginApi, cfg: AgentBrainPluginConfig) {
  return async (ctx: AgentEndCtx) => {
    if (ctx.trigger === "memory") return {};
    if (ctx.sessionKey?.includes(":memory-capture:")) return {};

    const agentId = resolveAgentId(cfg, ctx.sessionKey);

    // Phase 1: complete intentions that were triggered (and acted on) during this session.
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

    // Phase 2: run index heuristic and route candidates.
    const { user: msgUser, assistant } = lastExchange(ctx);
    const user = msgUser || (await loadLastUserPrompt(ctx.sessionKey));
    const candidates = indexCandidates(user, assistant);
    if (candidates.length === 0) return {};

    for (const row of candidates) {
      try {
        if (row.action === "set_intention") {
          await callMcpTool(
            cfg,
            api.rootDir,
            "set_intention",
            { agent_id: agentId, content: row.content, topic: row.topic ?? "" },
            ctx.sessionKey,
          );
        } else {
          const args: Record<string, unknown> = { ...row };
          delete args.action;
          delete args.topic;
          await callMcpTool(cfg, api.rootDir, "memory_write", args, ctx.sessionKey);
        }
      } catch (err) {
        api.logger.warn(`agent-brain: capture write failed: ${String(err)}`);
      }
    }
    return {};
  };
}
