import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { parseConfig, resolveAgentId, resolveSessionId } from "../config.ts";

describe("parseConfig", () => {
  it("requires url", () => {
    assert.throws(() => parseConfig({}));
  });

  it("parses defaults", () => {
    const c = parseConfig({ url: "https://memory.example.com/sse", apiKey: "k" });
    assert.equal(c.autoRecall, true);
    assert.equal(c.recallLimit, 8);
  });
});

describe("resolveAgentId", () => {
  it("uses fixed agentId", () => {
    const c = parseConfig({ url: "http://x/sse", agentId: "openclaw-alice" });
    assert.equal(resolveAgentId(c, "user:main"), "openclaw-alice");
  });

  it("derives from sessionKey", () => {
    const c = parseConfig({ url: "http://x/sse", agentPrefix: "openclaw" });
    assert.equal(resolveAgentId(c, "user:main"), "openclaw-user-main");
  });
});

describe("resolveSessionId", () => {
  it("prefixes session key", () => {
    assert.equal(resolveSessionId("abc"), "agent-brain-abc");
  });
});
