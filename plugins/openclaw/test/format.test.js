import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { formatRecallBlock } from "../format.ts";
import { saveLastUserPrompt, loadLastUserPrompt } from "../session-state.ts";
import os from "node:os";

describe("formatRecallBlock", () => {
  it("formats memory rows", () => {
    const block = formatRecallBlock(
      [{ subject_raw: "diet", content: "vegetarian", confidence: 0.9 }],
      8,
    );
    assert.ok(block.includes("vegetarian"));
    assert.ok(block.includes("untrusted-data"));
  });

  it("returns empty for no rows", () => {
    assert.equal(formatRecallBlock([], 8), "");
  });
});

describe("session-state /tmp migration", () => {
  it("saves and loads prompt from /tmp, not home dir", async () => {
    const key = "test-session-" + Date.now();
    await saveLastUserPrompt(key, "hello world");
    const loaded = await loadLastUserPrompt(key);
    assert.strictEqual(loaded, "hello world");
    // Verify path is under /tmp (os.tmpdir())
    const tmpdir = os.tmpdir();
    const safe = key.replace(/[^a-zA-Z0-9._-]+/g, "_");
    const { existsSync } = await import("node:fs");
    assert.ok(existsSync(`${tmpdir}/agent-brain-prompt-${safe}.txt`));
  });
});
