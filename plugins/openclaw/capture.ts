import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { indexCandidates } from "./format.js";
import type { PluginApi } from "./recall.js";
import { loadLastUserPrompt } from "./session-state.js";

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

    const { user: msgUser, assistant } = lastExchange(ctx);
    const user = msgUser || (await loadLastUserPrompt(ctx.sessionKey));
    const candidates = indexCandidates(user, assistant);
    if (candidates.length === 0) return {};

    for (const row of candidates) {
      try {
        const args: Record<string, unknown> = { ...row };
        await callMcpTool(cfg, api.rootDir, "memory_write", args, ctx.sessionKey);
      } catch (err) {
        api.logger.warn(`agent-brain: capture write failed: ${String(err)}`);
      }
    }
    return {};
  };
}
