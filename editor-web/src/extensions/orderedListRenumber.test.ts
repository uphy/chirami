import { describe, expect, it } from "vitest";
import { EditorState, TransactionSpec } from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { ensureSyntaxTree } from "@codemirror/language";
import { orderedListRenumber } from "./orderedListRenumber";

function apply(doc: string, spec: (s: EditorState) => TransactionSpec): string {
  const state = EditorState.create({ doc, extensions: [markdown({ base: markdownLanguage }), orderedListRenumber] });
  ensureSyntaxTree(state, state.doc.length, 5000);
  return state.update(spec(state)).state.doc.toString();
}

const deleteLine = (n: number) => (s: EditorState): TransactionSpec => {
  const line = s.doc.line(n);
  return { changes: { from: line.from, to: Math.min(line.to + 1, s.doc.length) }, userEvent: "delete" };
};

describe("orderedListRenumber", () => {
  it("renumbers from the old start when the first item is deleted", () => {
    expect(apply("1. a\n2. b\n3. c\n", deleteLine(1))).toBe("1. b\n2. c\n");
  });

  it("closes the gap when a middle item is deleted", () => {
    expect(apply("1. a\n2. b\n3. c\n", deleteLine(2))).toBe("1. a\n2. c\n");
  });

  it("keeps a list that starts at another number", () => {
    expect(apply("4. a\n5. b\n6. c\n", deleteLine(2))).toBe("4. a\n5. c\n");
  });

  it("respects a new first number typed by the user", () => {
    expect(apply("1. a\n2. b\n", () => ({ changes: { from: 0, to: 1, insert: "3" }, userEvent: "input.type" })))
      .toBe("3. a\n4. b\n");
  });

  it("leaves one-number lists alone", () => {
    expect(apply("1. a\n1. b\n1. c\n", deleteLine(2))).toBe("1. a\n1. c\n");
  });

  it("does not touch external updates or lists away from the edit", () => {
    const doc = "1. a\n3. b\n\npara\n";
    expect(apply(doc, (s) => ({ changes: { from: s.doc.length, insert: "x" }, userEvent: "external" }))).toBe(doc + "x");
    expect(apply(doc, (s) => ({ changes: { from: s.doc.length, insert: "x" }, userEvent: "input.type" }))).toBe(doc + "x");
  });

  it("renumbers nested ordered lists independently", () => {
    expect(apply("1. a\n\t1. x\n\t2. y\n\t3. z\n2. b\n", deleteLine(3))).toBe("1. a\n\t1. x\n\t2. z\n2. b\n");
  });
});
