import path from "node:path";
import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { resolveAgentId } from "./config.js";
import {
  formatRecallBlock,
  formatIntentionsBlock,
  extractTriggeredIds,
  type MemoryRow,
} from "./format.js";
import { saveLastUserPrompt, appendTriggeredIntentionIds } from "./session-state.js";
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

    const intentionsArgs = {
      agent_id: resolveAgentId(cfg, ctx.sessionKey),
      context_text: query,
    };

    const [recallRes, intentionsRes] = await Promise.allSettled([
      callMcpTool(cfg, api.rootDir, "memory_search", recallArgs, ctx.sessionKey),
      callMcpTool(cfg, api.rootDir, "check_intentions", intentionsArgs, ctx.sessionKey),
    ]);

    let recallBlock = "";
    if (recallRes.status === "fulfilled") {
      try {
        const parsed = JSON.parse(recallRes.value) as MemoryRow[] | { memories?: MemoryRow[] };
        const rows = Array.isArray(parsed) ? parsed : (parsed?.memories ?? []);
        recallBlock = formatRecallBlock(rows, cfg.recallLimit) ?? "";
      } catch {
        api.logger.warn("agent-brain: invalid memory_search JSON");
      }
    } else {
      api.logger.warn(`agent-brain: recall failed: ${String(recallRes.reason)}`);
    }

    let intentionsBlock = "";
    if (intentionsRes.status === "fulfilled") {
      const raw = intentionsRes.value;
      const triggeredIds = extractTriggeredIds(raw);
      if (triggeredIds.length > 0) {
        await appendTriggeredIntentionIds(ctx.sessionKey, triggeredIds).catch(() => {});
      }
      intentionsBlock = formatIntentionsBlock(raw);
    }

    const parts: string[] = [];
    if (firstCall && skillBlock) parts.push(skillBlock);
    if (recallBlock) parts.push(recallBlock);
    if (intentionsBlock) parts.push(intentionsBlock);

    if (parts.length === 0) return {};
    return { prependContext: parts.join("\n\n") };
  };
}
