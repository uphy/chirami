import { describe, expect, it } from "vitest";
import { EditorState } from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { ensureSyntaxTree } from "@codemirror/language";
import { listLineAt, parsePastedList, subtreeEnd } from "./listContext";

function state(doc: string): EditorState {
  const s = EditorState.create({ doc, extensions: [markdown({ base: markdownLanguage }), EditorState.tabSize.of(3)] });
  ensureSyntaxTree(s, s.doc.length, 5000);
  return s;
}

describe("parsePastedList", () => {
  it("returns depths for a pure list, normalizing space indentation", () => {
    expect(parsePastedList("- x\n- y\n  - z\n    - w\n")).toEqual([
      { depth: 0, text: "- x" },
      { depth: 0, text: "- y" },
      { depth: 1, text: "- z" },
      { depth: 2, text: "- w" },
    ]);
  });

  it("returns null when any line is not a list item", () => {
    expect(parsePastedList("- x\nplain")).toBeNull();
    expect(parsePastedList("just text")).toBeNull();
  });
});

describe("listLineAt", () => {
  it("finds marker, indent and content start (after a task box)", () => {
    const s = state("- a\n\t- [ ] task\n");
    const item = listLineAt(s, s.doc.line(2));
    expect(item?.indent).toBe("\t");
    expect(item?.marker).toBe("-");
    expect(s.sliceDoc(item!.contentStart, s.doc.line(2).to)).toBe("task");
  });

  it("returns null for non-list lines", () => {
    const s = state("para\n");
    expect(listLineAt(s, s.doc.line(1))).toBeNull();
  });
});

describe("subtreeEnd", () => {
  it("includes deeper lines and stops at the next sibling", () => {
    const s = state("- a\n- b\n\t- b1\n\t\t- b11\n- c\n");
    expect(subtreeEnd(s, 2)).toBe(4);
    expect(subtreeEnd(s, 5)).toBe(5);
  });
});
