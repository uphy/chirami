import { describe, expect, it } from "vitest";
import { cursorInSpan, parseCodeBlockInfo, sizeOptionsEq, tryParseJSON } from "./utils";

describe("parseCodeBlockInfo", () => {
  it("parses a bare language and lowercases it", () => {
    expect(parseCodeBlockInfo("JS")).toEqual({ lang: "js", options: {} });
  });

  it("returns an empty lang for an empty info string", () => {
    expect(parseCodeBlockInfo("")).toEqual({ lang: "", options: {} });
  });

  it("parses width and height options", () => {
    expect(parseCodeBlockInfo("excalidraw width=300 height=200")).toEqual({
      lang: "excalidraw",
      options: { width: 300, height: 200 },
    });
  });

  it("ignores non-numeric option values", () => {
    expect(parseCodeBlockInfo("mermaid width=abc")).toEqual({ lang: "mermaid", options: {} });
  });

  it("ignores zero and negative option values", () => {
    expect(parseCodeBlockInfo("mermaid width=0 height=-5")).toEqual({ lang: "mermaid", options: {} });
  });

  it("ignores options with no value and unknown keys", () => {
    expect(parseCodeBlockInfo("transcript width= depth=4 foo")).toEqual({
      lang: "transcript",
      options: {},
    });
  });

  it("tolerates surrounding whitespace", () => {
    expect(parseCodeBlockInfo("  transcript  width=120  ")).toEqual({
      lang: "transcript",
      options: { width: 120 },
    });
  });
});

describe("tryParseJSON", () => {
  it("parses valid JSON", () => {
    expect(tryParseJSON<{ a: number }>('{"a":1}')).toEqual({ a: 1 });
  });

  it("returns undefined for invalid JSON", () => {
    expect(tryParseJSON("{not json}")).toBeUndefined();
  });

  it("returns undefined for blank input", () => {
    expect(tryParseJSON("   ")).toBeUndefined();
  });
});

describe("cursorInSpan", () => {
  it("includes both boundaries", () => {
    expect(cursorInSpan(5, 5, 10)).toBe(true);
    expect(cursorInSpan(10, 5, 10)).toBe(true);
    expect(cursorInSpan(4, 5, 10)).toBe(false);
    expect(cursorInSpan(11, 5, 10)).toBe(false);
  });
});

describe("sizeOptionsEq", () => {
  it("compares width and height", () => {
    expect(sizeOptionsEq({ width: 1, height: 2 }, { width: 1, height: 2 })).toBe(true);
    expect(sizeOptionsEq({}, {})).toBe(true);
    expect(sizeOptionsEq({ width: 1 }, { width: 2 })).toBe(false);
    expect(sizeOptionsEq({ height: 1 }, {})).toBe(false);
  });
});
