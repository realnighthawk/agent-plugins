import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { formatRecallBlock, formatSearchBlock } from "../format.ts";
import { saveLastUserPrompt, loadLastUserPrompt } from "../session-state.ts";
import os from "node:os";

describe("formatRecallBlock", () => {
  it("formats EMU recall response with context tags and clusters", () => {
    const raw = JSON.stringify({
      query_hash: "abc123",
      emus: [{ episode_cluster_id: "cluster-1", activation_score: 0.85, support_count: 3 }],
      context_tags: ["morning-work"],
      duration_ms: 12,
    });
    const block = formatRecallBlock(raw, 8);
    assert.ok(block.includes("cluster-1"));
    assert.ok(block.includes("untrusted-data"));
    assert.ok(block.includes("morning-work"));
  });

  it("returns empty for empty emus and no context tags", () => {
    const raw = JSON.stringify({ query_hash: "abc", emus: [], context_tags: [] });
    assert.equal(formatRecallBlock(raw, 8), "");
  });

  it("returns empty for invalid JSON string", () => {
    assert.equal(formatRecallBlock("not-json", 8), "");
  });

  it("accepts MemoryRecallResponse object directly", () => {
    const resp = {
      emus: [{ episode_cluster_id: "cluster-x", activation_score: 0.7 }],
      context_tags: ["evening"],
    };
    const block = formatRecallBlock(resp, 8);
    assert.ok(block.includes("cluster-x"));
    assert.ok(block.includes("evening"));
  });
});

describe("formatSearchBlock", () => {
  it("formats entities and predicates", () => {
    const raw = JSON.stringify({
      entities: [{ name: "agent-brain", aliases: ["ab"] }],
      predicates: [{ name: "uses", is_root: true, description: "usage relation" }],
    });
    const block = formatSearchBlock(raw);
    assert.ok(block.includes("Known vocabulary"));
    assert.ok(block.includes("agent-brain"));
    assert.ok(block.includes("(ab)"));
    assert.ok(block.includes("uses (root)"));
  });

  it("returns empty for no entities or predicates", () => {
    const raw = JSON.stringify({ entities: [], predicates: [] });
    assert.equal(formatSearchBlock(raw), "");
  });

  it("returns empty for invalid JSON", () => {
    assert.equal(formatSearchBlock("bad-json"), "");
  });
});

describe("session-state /tmp migration", () => {
  it("saves and loads prompt from /tmp, not home dir", async () => {
    const key = "test-session-" + Date.now();
    await saveLastUserPrompt(key, "hello world");
    const loaded = await loadLastUserPrompt(key);
    assert.strictEqual(loaded, "hello world");
    const tmpdir = os.tmpdir();
    const safe = key.replace(/[^a-zA-Z0-9._-]+/g, "_");
    const { existsSync } = await import("node:fs");
    assert.ok(existsSync(`${tmpdir}/agent-brain-prompt-${safe}.txt`));
  });
});
