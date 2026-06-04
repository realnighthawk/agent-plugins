import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { formatRecallBlock, indexCandidates } from "../format.ts";

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

describe("indexCandidates", () => {
  it("captures preference statements", () => {
    const c = indexCandidates("I prefer morning runs before work", "ok");
    assert.equal(c.length, 1);
    assert.equal(c[0].signal_type, "user-stated");
  });

  it("skips boilerplate", () => {
    assert.equal(indexCandidates("thanks", "").length, 0);
  });
});
