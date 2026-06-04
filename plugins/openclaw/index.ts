import { parseConfig } from "./config.js";
import { createCaptureHook } from "./capture.js";
import { createRecallHook, type PluginApi } from "./recall.js";

/** Minimal API surface — full types from openclaw/plugin-sdk at runtime. */
type OpenClawPluginApi = PluginApi & {
  id: string;
  name: string;
  description?: string;
  pluginConfig?: Record<string, unknown>;
  on: (event: string, handler: (ctx: unknown) => Promise<unknown>) => void;
};

const nighthawkMemoryPlugin = {
  id: "agent-brain",
  name: "Agent Brain",
  description: "Hosted agent-brain MCP with auto recall and capture",
  kind: "memory" as const,

  register(api: OpenClawPluginApi) {
    const cfg = parseConfig(api.pluginConfig);

    if (cfg.autoRecall) {
      api.on("before_prompt_build", createRecallHook(api, cfg));
    }
    if (cfg.autoCapture) {
      api.on("agent_end", createCaptureHook(api, cfg));
    }

    const hooks = [
      cfg.autoRecall && "before_prompt_build",
      cfg.autoCapture && "agent_end",
    ].filter(Boolean);
    api.logger.info(
      `agent-brain: registered hooks: ${hooks.length ? hooks.join(", ") : "(none)"}`,
    );
  },
};

export default nighthawkMemoryPlugin;
