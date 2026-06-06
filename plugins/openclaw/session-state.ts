import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

function promptPath(sessionKey: string): string {
  const safe = sessionKey.replace(/[^a-zA-Z0-9._-]+/g, "_");
  return path.join(os.tmpdir(), `agent-brain-prompt-${safe}.txt`);
}

function triggeredPath(sessionKey: string): string {
  const safe = sessionKey.replace(/[^a-zA-Z0-9._-]+/g, "_");
  return path.join(os.tmpdir(), `agent-brain-triggered-intentions-${safe}.txt`);
}

export async function saveLastUserPrompt(
  sessionKey: string | undefined,
  prompt: string,
): Promise<void> {
  if (!sessionKey || !prompt.trim()) return;
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

export async function appendTriggeredIntentionIds(
  sessionKey: string | undefined,
  ids: string[],
): Promise<void> {
  if (!sessionKey || ids.length === 0) return;
  await fs.appendFile(triggeredPath(sessionKey), ids.join("\n") + "\n", "utf8");
}

export async function loadAndClearTriggeredIntentionIds(
  sessionKey: string | undefined,
): Promise<string[]> {
  if (!sessionKey) return [];
  const p = triggeredPath(sessionKey);
  try {
    const content = await fs.readFile(p, "utf8");
    await fs.unlink(p).catch(() => {});
    return content
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean);
  } catch {
    return [];
  }
}
