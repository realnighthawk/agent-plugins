import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { formatRecallBlock, formatSearchBlock } from "./format.js";

const MAX_BLOCK_CHARS = 4000;

export type SessionSkill = { block: string };

const _cache = new Map<string, SessionSkill>();

export async function getSessionSkill(
  cfg: AgentBrainPluginConfig,
  rootDir: string | undefined,
  sessionKey: string | undefined,
  cwdBasename: string,
): Promise<SessionSkill> {
  const key = sessionKey ?? "";
  const cached = _cache.get(key);
  if (cached) return cached;

  const [recallRes, searchRes] = await Promise.allSettled([
    callMcpTool(cfg, rootDir, "memory_recall", { query: cwdBasename, limit: 8 }, sessionKey),
    callMcpTool(cfg, rootDir, "memory_search", { query: cwdBasename, limit: 10 }, sessionKey),
  ]);

  const parts: string[] = [];

  if (recallRes.status === "fulfilled" && recallRes.value) {
    const block = formatRecallBlock(recallRes.value, 8);
    if (block) parts.push(block.slice(0, MAX_BLOCK_CHARS / 2));
  }

  if (searchRes.status === "fulfilled" && searchRes.value) {
    const block = formatSearchBlock(searchRes.value);
    if (block) parts.push(block.slice(0, MAX_BLOCK_CHARS / 2));
  }

  const combined = parts.join("\n\n");
  const result: SessionSkill = { block: combined.slice(0, MAX_BLOCK_CHARS) };
  _cache.set(key, result);
  return result;
}

export function clearSessionSkillCache(): void {
  _cache.clear();
}
