import { EditorState } from "@codemirror/state";
import { describe, expect, it } from "vitest";
import { computeFoldRange, headingFoldRange, listFoldRange } from "./foldMarkdown";

function stateOf(doc: string): EditorState {
  return EditorState.create({ doc });
}

function lineStart(state: EditorState, lineNum: number): number {
  return state.doc.line(lineNum).from;
}

describe("headingFoldRange", () => {
  it("folds a heading section up to the next heading of the same level", () => {
    const state = stateOf("# A\nbody\n# B\nbody2");
    const range = headingFoldRange(state, lineStart(state, 1));
    expect(range).toEqual({ from: state.doc.line(1).to, to: state.doc.line(2).to });
  });

  it("includes deeper subheadings in the folded section", () => {
    const state = stateOf("# A\n## B\nbody\n# C");
    const range = headingFoldRange(state, lineStart(state, 1));
    expect(range).toEqual({ from: state.doc.line(1).to, to: state.doc.line(3).to });
  });

  it("stops a subheading fold at a higher-level heading", () => {
    const state = stateOf("## A\nbody\n# B\nbody2");
    const range = headingFoldRange(state, lineStart(state, 1));
    expect(range).toEqual({ from: state.doc.line(1).to, to: state.doc.line(2).to });
  });

  it("folds the last section to the end of the document", () => {
    const state = stateOf("# A\nbody\nmore");
    const range = headingFoldRange(state, lineStart(state, 1));
    expect(range).toEqual({ from: state.doc.line(1).to, to: state.doc.line(3).to });
  });

  it("returns null for a heading with no content", () => {
    const state = stateOf("# A\n# B");
    expect(headingFoldRange(state, lineStart(state, 1))).toBeNull();
  });

  it("returns null for a non-heading line", () => {
    const state = stateOf("plain text\nbody");
    expect(headingFoldRange(state, lineStart(state, 1))).toBeNull();
  });

  it("requires whitespace after the hashes", () => {
    const state = stateOf("#nospace\nbody");
    expect(headingFoldRange(state, lineStart(state, 1))).toBeNull();
  });
});

describe("listFoldRange", () => {
  it("folds nested list items under a parent item", () => {
    const state = stateOf("- a\n  - b\n  - c\n- d");
    const range = listFoldRange(state, lineStart(state, 1));
    expect(range).toEqual({ from: state.doc.line(1).to, to: state.doc.line(3).to });
  });

  it("supports ordered list markers", () => {
    const state = stateOf("1. a\n   1. b\n2. c");
    const range = listFoldRange(state, lineStart(state, 1));
    expect(range).toEqual({ from: state.doc.line(1).to, to: state.doc.line(2).to });
  });

  it("skips blank lines inside the nested range", () => {
    const state = stateOf("- a\n\n  - b\n- c");
    const range = listFoldRange(state, lineStart(state, 1));
    expect(range).toEqual({ from: state.doc.line(1).to, to: state.doc.line(3).to });
  });

  it("returns null for a list item without children", () => {
    const state = stateOf("- a\n- b");
    expect(listFoldRange(state, lineStart(state, 1))).toBeNull();
  });

  it("returns null for a non-list line", () => {
    const state = stateOf("plain\n  indented");
    expect(listFoldRange(state, lineStart(state, 1))).toBeNull();
  });
});

describe("computeFoldRange", () => {
  it("returns null for out-of-range line numbers", () => {
    const state = stateOf("# A\nbody");
    expect(computeFoldRange(state, 0)).toBeNull();
    expect(computeFoldRange(state, 3)).toBeNull();
  });

  it("resolves a heading fold range", () => {
    const state = stateOf("# A\nbody");
    expect(computeFoldRange(state, 1)).toEqual({ from: state.doc.line(1).to, to: state.doc.line(2).to });
  });

  it("falls back to a list fold range", () => {
    const state = stateOf("- a\n  - b");
    expect(computeFoldRange(state, 1)).toEqual({ from: state.doc.line(1).to, to: state.doc.line(2).to });
  });

  it("returns null for a plain text line", () => {
    const state = stateOf("plain\nbody");
    expect(computeFoldRange(state, 1)).toBeNull();
  });
});
