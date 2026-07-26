import { GFM, parser } from "@lezer/markdown";
import { describe, expect, it } from "vitest";
import { WikiLink, wikiLinkDisplayText } from "./wikilink";

// Tests run in plain Node (no jsdom), so we exercise the parser and pure
// helpers only — DOM rendering/clicks are covered manually via the editor.
const wikiParser = parser.configure([GFM, WikiLink]);

function nodeNames(text: string): string[] {
  const names: string[] = [];
  wikiParser.parse(text).iterate({
    enter: (node) => {
      names.push(node.name);
    },
  });
  return names;
}

/** Returns [from, to] of the first WikiLink node, or null. */
function wikiLinkRange(text: string): [number, number] | null {
  let range: [number, number] | null = null;
  wikiParser.parse(text).iterate({
    enter: (node) => {
      if (node.name === "WikiLink" && range === null) {
        range = [node.from, node.to];
      }
    },
  });
  return range;
}

describe("WikiLink parser extension", () => {
  it("parses [[Page]] as a WikiLink with two WikiLinkMark delimiters", () => {
    const names = nodeNames("see [[Page]] now");
    expect(names).toContain("WikiLink");
    expect(names.filter((n) => n === "WikiLinkMark")).toHaveLength(2);
  });

  it("covers the full [[..]] span including brackets", () => {
    const text = "x [[Page]] y";
    expect(wikiLinkRange(text)).toEqual([text.indexOf("[["), text.indexOf("]]") + 2]);
  });

  it("parses aliases and headings inside a single node", () => {
    expect(nodeNames("[[Page|Alias]]")).toContain("WikiLink");
    expect(nodeNames("[[Page#Heading]]")).toContain("WikiLink");
  });

  it("does not create a WikiLink for empty [[]]", () => {
    expect(nodeNames("a [[]] b")).not.toContain("WikiLink");
  });

  it("does not create a WikiLink without a closing ]]", () => {
    expect(nodeNames("a [[Page b")).not.toContain("WikiLink");
  });

  it("does not treat a single [bracket] link as a WikiLink", () => {
    const names = nodeNames("[text](http://x)");
    expect(names).not.toContain("WikiLink");
    expect(names).toContain("Link");
  });
});

describe("wikiLinkDisplayText", () => {
  it("returns the alias when present", () => {
    expect(wikiLinkDisplayText("Page|Alias")).toBe("Alias");
  });

  it("returns the target when there is no alias", () => {
    expect(wikiLinkDisplayText("Page#Heading")).toBe("Page#Heading");
  });
});
