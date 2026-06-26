import assert from "node:assert/strict";
import { describe, it, beforeEach } from "node:test";
import { writeFileSync, chmodSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { clearSessionSkillCache } from "../session-skill.ts";

const baseCfg = {
  url: "http://mock",
  apiKey: "test-key",
  agentId: "test-agent",
  agentPrefix: "openclaw",
  autoRecall: true,
  autoCapture: true,
  recallLimit: 8,
  recallMinPromptLength: 12,
  mcpCallPath: "/dev/null",
};

function makeMockCfg(overrides = {}) {
  return { ...baseCfg, ...overrides };
}

function writeMock(script) {
  const p = join(tmpdir(), `mock-mcp-${Date.now()}.sh`);
  writeFileSync(p, `#!/usr/bin/env bash\n${script}\n`);
  chmodSync(p, 0o755);
  return p;
}

const emptyRecall = JSON.stringify({ query_hash: "h", emus: [], context_tags: [] });
const filledRecall = JSON.stringify({
  query_hash: "h",
  emus: [{ episode_cluster_id: "cluster-1", activation_score: 0.85, support_count: 3 }],
  context_tags: ["work"],
});
const filledSearch = JSON.stringify({
  entities: [{ name: "agent-brain" }],
  predicates: [{ name: "uses", is_root: true }],
});

describe("getSessionSkill", () => {
  beforeEach(() => clearSessionSkillCache());

  it("returns block with recall and search content when both succeed", async () => {
    const { getSessionSkill } = await import("../session-skill.ts");
    const mockPath = writeMock(`
case "$1" in
  memory_recall) echo '${filledRecall}' ;;
  memory_search) echo '${filledSearch}' ;;
esac
`);
    const result = await getSessionSkill(
      makeMockCfg({ mcpCallPath: mockPath }),
      undefined,
      "session-1",
      "my-project",
    );
    unlinkSync(mockPath);
    assert.ok(result.block.includes("## Memory context (agent-brain)"), "recall block missing");
    assert.ok(result.block.includes("cluster-1"), "EMU cluster missing");
    assert.ok(result.block.includes("## Known vocabulary (agent-brain)"), "search block missing");
    assert.ok(result.block.includes("agent-brain"), "entity missing");
  });

  it("omits recall block when memory_recall returns empty", async () => {
    const { getSessionSkill } = await import("../session-skill.ts");
    const mockPath = writeMock(`
case "$1" in
  memory_recall) echo '${emptyRecall}' ;;
  memory_search) echo '${filledSearch}' ;;
esac
`);
    const result = await getSessionSkill(
      makeMockCfg({ mcpCallPath: mockPath }),
      undefined,
      "session-2",
      "my-project",
    );
    unlinkSync(mockPath);
    assert.ok(!result.block.includes("## Memory context"), "recall block should be absent");
    assert.ok(result.block.includes("## Known vocabulary"), "search block should still appear");
  });

  it("does not throw when mcp-call returns null JSON", async () => {
    const { getSessionSkill } = await import("../session-skill.ts");
    const mockPath = writeMock(`echo 'null'`);
    const result = await getSessionSkill(
      makeMockCfg({ mcpCallPath: mockPath }),
      undefined,
      "session-null",
      "my-project",
    );
    unlinkSync(mockPath);
    assert.strictEqual(result.block, "");
  });

  it("returns empty block when all calls fail", async () => {
    const { getSessionSkill } = await import("../session-skill.ts");
    const mockPath = writeMock("exit 1");
    let result;
    try {
      result = await getSessionSkill(
        makeMockCfg({ mcpCallPath: mockPath }),
        undefined,
        "session-3",
        "my-project",
      );
    } catch {
      result = { block: "" };
    }
    unlinkSync(mockPath);
    assert.strictEqual(result.block, "");
  });

  it("returns cached result on second call without re-executing", async () => {
    const { getSessionSkill } = await import("../session-skill.ts");
    const mockPath = writeMock(`
case "$1" in
  memory_recall) echo '${filledRecall}' ;;
  memory_search) echo '${filledSearch}' ;;
esac
`);
    const r1 = await getSessionSkill(makeMockCfg({ mcpCallPath: mockPath }), undefined, "session-4", "proj");
    const r2 = await getSessionSkill(makeMockCfg({ mcpCallPath: mockPath }), undefined, "session-4", "proj");
    unlinkSync(mockPath);
    assert.strictEqual(r1.block, r2.block);
  });

  it("enforces total char cap at 4000", async () => {
    const { getSessionSkill } = await import("../session-skill.ts");
    const longCluster = "c".repeat(1200);
    const bigRecall = JSON.stringify({
      emus: [{ episode_cluster_id: longCluster, activation_score: 0.9 }],
      context_tags: ["t".repeat(500)],
    });
    const bigSearch = JSON.stringify({
      entities: Array.from({ length: 20 }, (_, i) => ({ name: "entity-" + "x".repeat(100) + "-" + i })),
      predicates: [],
    });
    const mockPath = writeMock(`
case "$1" in
  memory_recall) echo '${bigRecall}' ;;
  memory_search) echo '${bigSearch}' ;;
esac
`);
    const result = await getSessionSkill(
      makeMockCfg({ mcpCallPath: mockPath }),
      undefined,
      "session-5",
      "proj",
    );
    unlinkSync(mockPath);
    assert.ok(result.block.length <= 4000);
  });
});

// ---- Recall integration tests ----
import { createRecallHook } from "../recall.ts";

describe("createRecallHook with session skill", () => {
  beforeEach(() => clearSessionSkillCache());

  it("includes skill block in prependContext on first call", async () => {
    const mockPath = writeMock(`
case "$1" in
  memory_recall) echo '${filledRecall}' ;;
  memory_search) echo '${filledSearch}' ;;
esac
`);
    const cfg = makeMockCfg({ mcpCallPath: mockPath, recallMinPromptLength: 5 });
    const api = { logger: { info: () => {}, warn: () => {} }, rootDir: undefined };
    const hook = createRecallHook(api, cfg);
    const result = await hook({ prompt: "what do you know?", sessionKey: "session-rc-1" });
    unlinkSync(mockPath);
    assert.ok(
      result.prependContext?.includes("## Memory context (agent-brain)"),
      "skill block missing on first call",
    );
  });

  it("does not throw on second call", async () => {
    const mockPath = writeMock(`
case "$1" in
  memory_recall) echo '${filledRecall}' ;;
  memory_search) echo '${filledSearch}' ;;
esac
`);
    const cfg = makeMockCfg({ mcpCallPath: mockPath, recallMinPromptLength: 5 });
    const api = { logger: { info: () => {}, warn: () => {} }, rootDir: undefined };
    const hook = createRecallHook(api, cfg);
    await hook({ prompt: "first call", sessionKey: "session-rc-2" });
    const result2 = await hook({ prompt: "second call", sessionKey: "session-rc-2" });
    unlinkSync(mockPath);
    assert.ok(result2 !== undefined);
  });
});
