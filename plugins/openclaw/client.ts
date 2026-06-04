import { execFile } from "node:child_process";
import { promisify } from "node:util";
import path from "node:path";
import type { AgentBrainPluginConfig } from "./config.js";
import { resolveAgentId, resolveSessionId } from "./config.js";

const execFileAsync = promisify(execFile);

export function mcpCallPath(cfg: AgentBrainPluginConfig, pluginRoot?: string): string {
  if (cfg.mcpCallPath) return cfg.mcpCallPath;
  if (pluginRoot) return path.join(pluginRoot, "bin", "mcp-call");
  return "mcp-call";
}

export function buildMcpEnv(
  cfg: AgentBrainPluginConfig,
  sessionKey?: string,
): Record<string, string> {
  const env: Record<string, string> = {
    NIGHTHAWK_MCP_URL: cfg.url,
    NIGHTHAWK_AGENT_ID: resolveAgentId(cfg, sessionKey),
    NIGHTHAWK_SESSION_ID: resolveSessionId(sessionKey),
  };
  if (cfg.jwt) env.NIGHTHAWK_JWT = cfg.jwt;
  else if (cfg.apiKey) env.NIGHTHAWK_API_KEY = cfg.apiKey;
  return env;
}

export async function callMcpTool(
  cfg: AgentBrainPluginConfig,
  pluginRoot: string | undefined,
  tool: string,
  args: Record<string, unknown>,
  sessionKey?: string,
): Promise<string> {
  const bin = mcpCallPath(cfg, pluginRoot);
  const env = { ...process.env, ...buildMcpEnv(cfg, sessionKey) };
  const { stdout } = await execFileAsync(bin, [tool, JSON.stringify(args)], {
    env,
    timeout: 25_000,
    maxBuffer: 4 * 1024 * 1024,
  });
  return stdout.trim();
}
