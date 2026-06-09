import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { AgentBrainPluginConfig } from "./config.js";
import { callMcpTool } from "./client.js";
import { formatEntityTypesBlock } from "./format.js";

const MAX_TIER_CHARS = 1600;
const MAX_TOTAL_CHARS = 4800;

type TierEntry = { header: string; raw: string };
export type SessionSkill = { block: string; subjects: string[] };

function extractTierText(raw: string): string {
  if (!raw.trim()) return "";
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed === "string") return parsed;
    if (parsed !== null && typeof parsed === "object") {
      const p = parsed as Record<string, unknown>;
      for (const key of ["content", "Body", "text", "profile", "summary"]) {
        if (typeof p[key] === "string") return p[key] as string;
      }
      const items = Array.isArray(parsed)
        ? (parsed as Record<string, unknown>[])
        : Array.isArray(p.memories)
          ? (p.memories as Record<string, unknown>[])
          : Array.isArray(p.preferences)
            ? (p.preferences as Record<string, unknown>[])
            : null;
      if (items) {
        return items
          .map((m) => {
            const subj = String(m.subject_raw ?? m.subject ?? m.Name ?? "fact");
            const content = String(m.content ?? m.text ?? m.Body ?? m.value ?? "");
            return `- [${subj}] ${content}`;
          })
          .join("\n");
      }
    }
  } catch {
    return raw.trim();
  }
  return "";
}

function extractSubjects(raw: string): string[] {
  if (!raw.trim()) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    if (parsed === null || typeof parsed !== "object") return [];
    const items = Array.isArray(parsed)
      ? (parsed as Record<string, unknown>[])
      : (parsed as Record<string, unknown>).memories
          ? ((parsed as Record<string, unknown>).memories as Record<string, unknown>[])
          : (parsed as Record<string, unknown>).preferences
            ? ((parsed as Record<string, unknown>).preferences as Record<string, unknown>[])
            : [];
    return items
      .map((m) => String(m.subject_raw ?? m.subject ?? ""))
      .filter(Boolean);
  } catch {
    return [];
  }
}

function buildBlock(tiers: TierEntry[]): { block: string; subjects: string[] } {
  const sections: string[] = [];
  const subjects: string[] = [];
  let totalChars = 0;

  for (const tier of tiers) {
    const text = extractTierText(tier.raw).slice(0, MAX_TIER_CHARS).trim();
    subjects.push(...extractSubjects(tier.raw));
    if (!text) continue;
    const section = `${tier.header}\n${text}`;
    // Account for "\n\n" separator that join() will add between sections
    const separatorCost = sections.length > 0 ? 2 : 0;
    const remaining = MAX_TOTAL_CHARS - totalChars - separatorCost;
    if (remaining <= tier.header.length + 20) break;
    const pushed = section.length > remaining ? section.slice(0, remaining) : section;
    sections.push(pushed);
    totalChars += pushed.length + separatorCost;
  }

  return { block: sections.join("\n\n"), subjects };
}

// In-process cache: one entry per sessionKey, populated on first call.
const _cache = new Map<string, SessionSkill>();

async function readPluginSkill(rootDir: string | undefined): Promise<string> {
  const skillsDir = rootDir
    ? path.join(rootDir, "skills")
    : path.join(path.dirname(fileURLToPath(import.meta.url)), "skills");
  try {
    return await readFile(path.join(skillsDir, "agent-brain-openclaw.md"), "utf8");
  } catch {
    return "";
  }
}

export async function getSessionSkill(
  cfg: AgentBrainPluginConfig,
  rootDir: string | undefined,
  sessionKey: string | undefined,
  cwdBasename: string,
): Promise<SessionSkill> {
  const key = sessionKey ?? "";
  const cached = _cache.get(key);
  if (cached) return cached;

  const [agentRes, userRes, projectRes, entityTypesRes] = await Promise.allSettled([
    callMcpTool(
      cfg,
      rootDir,
      "retrieve_skills_for_context",
      { agent_id: cfg.agentId ?? cfg.agentPrefix ?? "unknown", query: "agent session context" },
      sessionKey,
    ),
    callMcpTool(cfg, rootDir, "memory_preference_profile", {}, sessionKey),
    callMcpTool(
      cfg,
      rootDir,
      "memory_search",
      { query: cwdBasename, limit: 6, use_graph: true },
      sessionKey,
    ),
    callMcpTool(
      cfg,
      rootDir,
      "list_entity_types",
      { agent_id: cfg.agentId ?? cfg.agentPrefix ?? "unknown" },
      sessionKey,
    ),
  ]);

  const tiers: TierEntry[] = [
    { header: "## Agent context", raw: agentRes.status === "fulfilled" ? agentRes.value : "" },
    { header: "## Your profile", raw: userRes.status === "fulfilled" ? userRes.value : "" },
    { header: "## Project context", raw: projectRes.status === "fulfilled" ? projectRes.value : "" },
  ];

  const memoryBlock = buildBlock(tiers);
  const pluginSkill = await readPluginSkill(rootDir);
  const entityTypesBlock =
    entityTypesRes.status === "fulfilled" ? formatEntityTypesBlock(entityTypesRes.value) : "";

  let block = pluginSkill
    ? memoryBlock.block
      ? `${pluginSkill}\n\n${memoryBlock.block}`
      : pluginSkill
    : memoryBlock.block;
  if (entityTypesBlock) {
    block = block ? `${block}\n\n${entityTypesBlock}` : entityTypesBlock;
  }

  const result: SessionSkill = { block, subjects: memoryBlock.subjects };
  _cache.set(key, result);
  return result;
}

export function clearSessionSkillCache(): void {
  _cache.clear();
}
