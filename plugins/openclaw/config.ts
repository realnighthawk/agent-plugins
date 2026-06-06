export type AgentBrainPluginConfig = {
  url: string;
  apiKey?: string;
  jwt?: string;
  agentId?: string;
  agentPrefix: string;
  autoRecall: boolean;
  autoCapture: boolean;
  recallLimit: number;
  recallMinPromptLength: number;
  mcpCallPath?: string;
};

const defaults = {
  agentPrefix: "openclaw",
  autoRecall: true,
  autoCapture: true,
  recallLimit: 8,
  recallMinPromptLength: 12,
};

export function parseConfig(raw: Record<string, unknown> | undefined): AgentBrainPluginConfig {
  const c = raw ?? {};
  const rawUrl = String(c.url ?? "").trim();
  const url = (rawUrl && !rawUrl.startsWith("${") ? rawUrl : process.env.NIGHTHAWK_MCP_URL ?? "");
  if (!url) {
    throw new Error("agent-brain: plugins.entries.agent-brain.config.url (or NIGHTHAWK_MCP_URL) is required");
  }
  return {
    url,
    apiKey: pickString(c.apiKey, process.env.NIGHTHAWK_API_KEY),
    jwt: pickString(c.jwt, process.env.NIGHTHAWK_JWT),
    agentId: pickString(c.agentId, process.env.NIGHTHAWK_AGENT_ID),
    agentPrefix: pickString(c.agentPrefix, process.env.NIGHTHAWK_AGENT_PREFIX) ?? defaults.agentPrefix,
    autoRecall: bool(c.autoRecall, defaults.autoRecall),
    autoCapture: bool(c.autoCapture, defaults.autoCapture),
    recallLimit: num(c.recallLimit, defaults.recallLimit),
    recallMinPromptLength: num(c.recallMinPromptLength, defaults.recallMinPromptLength),
    mcpCallPath: pickString(c.mcpCallPath, process.env.NIGHTHAWK_MCP_CALL),
  };
}

function pickString(...vals: (unknown | undefined)[]): string | undefined {
  for (const v of vals) {
    if (typeof v === "string") {
      const s = v.trim();
      if (s && !s.startsWith("${")) return s;
    }
  }
  return undefined;
}

function bool(v: unknown, d: boolean): boolean {
  return typeof v === "boolean" ? v : d;
}

function num(v: unknown, d: number): number {
  return typeof v === "number" && !Number.isNaN(v) ? v : d;
}

/** Agent scope: fixed agentId or openclaw-<prefix>-<session-slug> */
export function resolveAgentId(cfg: AgentBrainPluginConfig, sessionKey?: string): string {
  if (cfg.agentId) return cfg.agentId;
  if (sessionKey) {
    const slug = sessionKey.replace(/[^a-zA-Z0-9]+/g, "-").replace(/^-|-$/g, "");
    return `${cfg.agentPrefix}-${slug}`;
  }
  return cfg.agentPrefix;
}

export function resolveSessionId(sessionKey?: string): string {
  if (sessionKey) return `agent-brain-${sessionKey}`;
  return `agent-brain-${Date.now()}`;
}
