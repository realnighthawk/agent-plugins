import path from "node:path";
import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { formatRecallBlock, type MemoryRow } from "./format.js";
import { saveLastUserPrompt } from "./session-state.js";
import { getSessionSkill } from "./session-skill.js";

export type PluginApi = {
  rootDir?: string;
  logger: { info: (msg: string) => void; warn: (msg: string) => void };
};

export type BeforePromptBuildCtx = {
  prompt?: string;
  sessionKey?: string;
  trigger?: string;
};

// Track which sessions have had their skill block injected already.
const _initializedSessions = new Set<string>();

export function createRecallHook(api: PluginApi, cfg: AgentBrainPluginConfig) {
  return async (ctx: BeforePromptBuildCtx) => {
    if (ctx.trigger === "memory") return {};

    const prompt = (ctx.prompt ?? "").trim();
    if (prompt.length < cfg.recallMinPromptLength) return {};

    await saveLastUserPrompt(ctx.sessionKey, prompt);

    const sessionKey = ctx.sessionKey ?? "";
    const firstCall = !_initializedSessions.has(sessionKey);
    if (firstCall) _initializedSessions.add(sessionKey);

    const cwdBasename = path.basename(process.cwd());
    const { block: skillBlock, subjects } = await getSessionSkill(
      cfg,
      api.rootDir,
      ctx.sessionKey,
      cwdBasename,
    ).catch(() => ({ block: "", subjects: [] as string[] }));

    const query = prompt.replace(/\s+/g, " ").slice(0, 500);
    const recallArgs: Record<string, unknown> = {
      query,
      limit: cfg.recallLimit,
      use_graph: true,
    };
    if (subjects.length > 0) {
      recallArgs.exclude_subjects = subjects;
    }

    let recallBlock = "";
    try {
      const raw = await callMcpTool(cfg, api.rootDir, "memory_search", recallArgs, ctx.sessionKey);
      let parsed: MemoryRow[] | { memories?: MemoryRow[] };
      try {
        parsed = JSON.parse(raw) as MemoryRow[] | { memories?: MemoryRow[] };
      } catch {
        api.logger.warn("agent-brain: invalid memory_search JSON");
        parsed = [];
      }
      recallBlock =
        formatRecallBlock(Array.isArray(parsed) ? parsed : (parsed.memories ?? []), cfg.recallLimit) ?? "";
    } catch (err) {
      api.logger.warn(`agent-brain: recall failed: ${String(err)}`);
    }

    const parts: string[] = [];
    if (firstCall && skillBlock) parts.push(skillBlock);
    if (recallBlock) parts.push(recallBlock);

    if (parts.length === 0) return {};
    return { prependContext: parts.join("\n\n") };
  };
}
