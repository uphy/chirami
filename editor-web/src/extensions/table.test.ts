import { markdown } from "@codemirror/lang-markdown";
import { EditorState } from "@codemirror/state";
import { GFM } from "@lezer/markdown";
import { describe, expect, it } from "vitest";
import { cellDocPos } from "./table";

function stateOf(doc: string): EditorState {
  return EditorState.create({ doc, extensions: [markdown({ extensions: GFM })] });
}

const TABLE = "| aa | bb |\n| --- | --- |\n| cc |  |\n| dd | ee |";

describe("cellDocPos", () => {
  it("maps a header cell to the end of its content", () => {
    const state = stateOf(TABLE);
    expect(cellDocPos(state, 0, 0, 0)).toBe(TABLE.indexOf("aa") + 2);
    expect(cellDocPos(state, 0, 0, 1)).toBe(TABLE.indexOf("bb") + 2);
  });

  it("maps data row cells, skipping the delimiter line", () => {
    const state = stateOf(TABLE);
    expect(cellDocPos(state, 0, 1, 0)).toBe(TABLE.indexOf("cc") + 2);
    expect(cellDocPos(state, 0, 2, 1)).toBe(TABLE.indexOf("ee") + 2);
  });

  it("lands just after the opening pipe for an empty cell", () => {
    const state = stateOf(TABLE);
    // Row "| cc |  |": empty second cell starts after the pipe following "cc".
    expect(cellDocPos(state, 0, 1, 1)).toBe(TABLE.indexOf("cc") + 4);
  });

  it("falls back to the row end for an out-of-range cell index", () => {
    const state = stateOf(TABLE);
    const headerLineEnd = TABLE.indexOf("\n");
    expect(cellDocPos(state, 0, 0, 9)).toBe(headerLineEnd);
  });

  it("falls back to the table start for an out-of-range row index", () => {
    const state = stateOf(TABLE);
    expect(cellDocPos(state, 0, 9, 0)).toBe(0);
  });

  it("resolves a table that does not start at the document start", () => {
    const doc = `# heading\n\n${TABLE}`;
    const state = stateOf(doc);
    const tableFrom = doc.indexOf("| aa");
    expect(cellDocPos(state, tableFrom, 1, 0)).toBe(doc.indexOf("cc") + 2);
  });
});
