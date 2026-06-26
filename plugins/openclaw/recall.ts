import path from "node:path";
import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { formatRecallBlock } from "./format.js";
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
    const { block: skillBlock } = await getSessionSkill(
      cfg,
      api.rootDir,
      ctx.sessionKey,
      cwdBasename,
    ).catch(() => ({ block: "" }));

    const query = prompt.replace(/\s+/g, " ").slice(0, 500);
    const recallResult = await callMcpTool(
      cfg,
      api.rootDir,
      "memory_recall",
      { query, limit: cfg.recallLimit },
      ctx.sessionKey,
    ).catch((err: unknown) => {
      api.logger.warn(`agent-brain: recall failed: ${String(err)}`);
      return "";
    });

    const recallBlock = recallResult ? formatRecallBlock(recallResult, cfg.recallLimit) : "";

    const parts: string[] = [];
    if (firstCall && skillBlock) parts.push(skillBlock);
    if (recallBlock) parts.push(recallBlock);

    if (parts.length === 0) return {};
    return { prependContext: parts.join("\n\n") };
  };
}
