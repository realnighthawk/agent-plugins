import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { formatRecallBlock, type MemoryRow } from "./format.js";
import { saveLastUserPrompt } from "./session-state.js";

export type PluginApi = {
  rootDir?: string;
  logger: { info: (msg: string) => void; warn: (msg: string) => void };
};

export type BeforePromptBuildCtx = {
  prompt?: string;
  sessionKey?: string;
  trigger?: string;
};

export function createRecallHook(api: PluginApi, cfg: AgentBrainPluginConfig) {
  return async (ctx: BeforePromptBuildCtx) => {
    if (ctx.trigger === "memory") return {};

    const prompt = (ctx.prompt ?? "").trim();
    if (prompt.length < cfg.recallMinPromptLength) return {};

    await saveLastUserPrompt(ctx.sessionKey, prompt);

    const query = prompt.replace(/\s+/g, " ").slice(0, 500);
    const args: Record<string, unknown> = {
      query,
      limit: cfg.recallLimit,
      use_graph: true,
    };

    try {
      const raw = await callMcpTool(
        cfg,
        api.rootDir,
        "memory_search",
        args,
        ctx.sessionKey,
      );
      let parsed: MemoryRow[] | { memories?: MemoryRow[] };
      try {
        parsed = JSON.parse(raw) as MemoryRow[] | { memories?: MemoryRow[] };
      } catch {
        api.logger.warn(`agent-brain: invalid memory_search JSON`);
        return {};
      }
      const block = formatRecallBlock(
        Array.isArray(parsed) ? parsed : (parsed.memories ?? []),
        cfg.recallLimit,
      );
      if (!block) return {};
      return { prependContext: block };
    } catch (err) {
      api.logger.warn(`agent-brain: recall failed: ${String(err)}`);
      return {};
    }
  };
}
