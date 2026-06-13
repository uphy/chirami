import { GFM, parser } from "@lezer/markdown";
import { describe, expect, it } from "vitest";
import { Highlight } from "./highlight";

// Tests run in plain Node (no jsdom), so we exercise the parser only — the
// <mark> DOM rendering in inlineMarkdown.ts is covered manually via the editor.
const highlightParser = parser.configure([GFM, Highlight]);

function nodeNames(text: string): string[] {
  const names: string[] = [];
  highlightParser.parse(text).iterate({
    enter: (node) => {
      names.push(node.name);
    },
  });
  return names;
}

describe("Highlight parser extension", () => {
  it("parses ==text== as a Highlight node with HighlightMark delimiters", () => {
    const names = nodeNames("a ==hi== b");
    expect(names).toContain("Highlight");
    expect(names.filter((name) => name === "HighlightMark")).toHaveLength(2);
  });

  it("does not treat ~~text~~ as a Highlight (no collision with Strikethrough)", () => {
    const names = nodeNames("a ~~no~~ b");
    expect(names).toContain("Strikethrough");
    expect(names).not.toContain("Highlight");
  });

  it("does not create a Highlight for a single = pair", () => {
    const names = nodeNames("a =not= b");
    expect(names).not.toContain("Highlight");
  });

  it("does not open a highlight at a triple ===", () => {
    const names = nodeNames("===x");
    expect(names).not.toContain("Highlight");
  });

  it("keeps highlight and strikethrough independent on the same line", () => {
    const names = nodeNames("==hi== and ~~bye~~");
    expect(names).toContain("Highlight");
    expect(names).toContain("Strikethrough");
  });
});
