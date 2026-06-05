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

describe("getSessionSkill", () => {
  beforeEach(() => clearSessionSkillCache());

  it("returns block with all three headers when all tiers succeed", async () => {
    const { getSessionSkill } = await import("../session-skill.ts");
    const mockPath = writeMock(`
case "$1" in
  retrieve_skills_for_context) echo '{"content":"agent rules"}' ;;
  memory_preference_profile) echo '[{"subject_raw":"diet","content":"vegetarian"}]' ;;
  memory_search) echo '[{"subject_raw":"repo","content":"uses TDD"}]' ;;
esac
`);
    const result = await getSessionSkill(
      makeMockCfg({ mcpCallPath: mockPath }),
      undefined,
      "session-1",
      "my-project",
    );
    unlinkSync(mockPath);
    assert.ok(result.block.includes("## Agent context"));
    assert.ok(result.block.includes("## Your profile"));
    assert.ok(result.block.includes("## Project context"));
    assert.ok(result.subjects.includes("diet"));
  });

  it("omits a tier when it returns empty", async () => {
    const { getSessionSkill } = await import("../session-skill.ts");
    const mockPath = writeMock(`
case "$1" in
  retrieve_skills_for_context) echo '{"content":"agent rules"}' ;;
  memory_preference_profile) echo '{}' ;;
  memory_search) echo '[]' ;;
esac
`);
    const result = await getSessionSkill(
      makeMockCfg({ mcpCallPath: mockPath }),
      undefined,
      "session-2",
      "my-project",
    );
    unlinkSync(mockPath);
    assert.ok(result.block.includes("## Agent context"));
    assert.ok(!result.block.includes("## Your profile"));
    assert.ok(!result.block.includes("## Project context"));
  });

  it("returns empty block when all tiers fail", async () => {
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
      result = { block: "", subjects: [] };
    }
    unlinkSync(mockPath);
    assert.strictEqual(result.block, "");
  });

  it("returns cached result on second call without re-executing", async () => {
    const { getSessionSkill } = await import("../session-skill.ts");
    const mockPath = writeMock(`
case "$1" in
  *) echo '{"content":"rules"}' ;;
esac
`);
    const r1 = await getSessionSkill(makeMockCfg({ mcpCallPath: mockPath }), undefined, "session-4", "proj");
    const r2 = await getSessionSkill(makeMockCfg({ mcpCallPath: mockPath }), undefined, "session-4", "proj");
    unlinkSync(mockPath);
    assert.strictEqual(r1.block, r2.block);
  });

  it("enforces total char cap at 4800", async () => {
    const { getSessionSkill } = await import("../session-skill.ts");
    const longContent = "x".repeat(2000);
    const mockPath = writeMock(`
case "$1" in
  retrieve_skills_for_context) echo '{"content":"${longContent}"}' ;;
  memory_preference_profile) echo '[{"subject_raw":"pref","content":"${longContent}"}]' ;;
  memory_search) echo '[{"subject_raw":"proj","content":"${longContent}"}]' ;;
esac
`);
    const result = await getSessionSkill(
      makeMockCfg({ mcpCallPath: mockPath }),
      undefined,
      "session-5",
      "proj",
    );
    unlinkSync(mockPath);
    assert.ok(result.block.length <= 4800);
  });
});
