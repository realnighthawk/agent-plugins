import fs from "node:fs/promises";
import path from "node:path";

function stateDir(): string {
  return (
    process.env.NIGHTHAWK_OPENCLAW_STATE ??
    path.join(process.env.HOME ?? "/tmp", ".openclaw", "agent-brain-state")
  );
}

function promptPath(sessionKey: string): string {
  const safe = sessionKey.replace(/[^a-zA-Z0-9._-]+/g, "_");
  return path.join(stateDir(), `last-prompt-${safe}.txt`);
}

export async function saveLastUserPrompt(
  sessionKey: string | undefined,
  prompt: string,
): Promise<void> {
  if (!sessionKey || !prompt.trim()) return;
  await fs.mkdir(stateDir(), { recursive: true });
  await fs.writeFile(promptPath(sessionKey), prompt, "utf8");
}

export async function loadLastUserPrompt(
  sessionKey: string | undefined,
): Promise<string> {
  if (!sessionKey) return "";
  try {
    return await fs.readFile(promptPath(sessionKey), "utf8");
  } catch {
    return "";
  }
}
