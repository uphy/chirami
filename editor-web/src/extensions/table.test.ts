import { markdown } from "@codemirror/lang-markdown";
import { ChangeSet, EditorState } from "@codemirror/state";
import { GFM } from "@lezer/markdown";
import { describe, expect, it } from "vitest";
import {
  buildEmptyRowMarkdown,
  computeCellCommit,
  countColumns,
  escapeCell,
  findTableByMarkdown,
  nextCellLocation,
  resolveCellRange,
  splitTableRow,
  tableHasLinePrefix,
  unescapeCell,
} from "./table";
import type { CellChange } from "./table";

function stateOf(doc: string): EditorState {
  return EditorState.create({ doc, extensions: [markdown({ extensions: GFM })] });
}

function applyChanges(state: EditorState, changes: CellChange[]): string {
  return state.update({ changes }).state.doc.toString();
}

const TABLE = "| aa | bb |\n| --- | --- |\n| cc |  |\n| dd | ee |";

describe("resolveCellRange", () => {
  it("resolves header and data cells to their content extents", () => {
    const state = stateOf(TABLE);
    for (const [row, col, text] of [[0, 0, "aa"], [0, 1, "bb"], [1, 0, "cc"], [2, 1, "ee"]] as const) {
      const range = resolveCellRange(state, 0, row, col);
      expect(range).not.toBeNull();
      expect(state.sliceDoc(range!.from, range!.to)).toBe(text);
      expect(range!.empty).toBe(false);
    }
  });

  it("resolves an empty cell to the whitespace span between pipes", () => {
    const state = stateOf(TABLE);
    const range = resolveCellRange(state, 0, 1, 1);
    expect(range).not.toBeNull();
    expect(range!.empty).toBe(true);
    expect(range!.closedByPipe).toBe(true);
    expect(state.sliceDoc(range!.from, range!.to).trim()).toBe("");
  });

  it("handles rows without leading pipes", () => {
    const doc = "aa | bb\n--- | ---\ncc | dd";
    const state = stateOf(doc);
    const range = resolveCellRange(state, 0, 1, 1);
    expect(range).not.toBeNull();
    expect(state.sliceDoc(range!.from, range!.to)).toBe("dd");
  });

  it("resolves a trailing empty slot without a closing pipe", () => {
    const doc = "| aa | bb |\n| --- | --- |\n| cc |";
    const state = stateOf(doc);
    const range = resolveCellRange(state, 0, 1, 1);
    expect(range).not.toBeNull();
    expect(range!.empty).toBe(true);
    expect(range!.closedByPipe).toBe(false);
    expect(range!.missingPipes).toBe(0);
  });

  it("synthesizes missing pipe slots for ragged rows", () => {
    const doc = "| a | b | c |\n| --- | --- | --- |\n| d |";
    const state = stateOf(doc);
    const range = resolveCellRange(state, 0, 1, 2);
    expect(range).not.toBeNull();
    expect(range!.empty).toBe(true);
    expect(range!.missingPipes).toBe(1);
  });

  it("keeps a cell containing an escaped pipe as a single slot", () => {
    const doc = "| a\\|b | c |\n| --- | --- |\n| d | e |";
    const state = stateOf(doc);
    const range = resolveCellRange(state, 0, 0, 0);
    expect(range).not.toBeNull();
    expect(state.sliceDoc(range!.from, range!.to)).toBe("a\\|b");
    const second = resolveCellRange(state, 0, 0, 1);
    expect(state.sliceDoc(second!.from, second!.to)).toBe("c");
  });

  it("handles single-column tables", () => {
    const state = stateOf("| a |\n| --- |\n| b |");
    const range = resolveCellRange(state, 0, 1, 0);
    expect(state.sliceDoc(range!.from, range!.to)).toBe("b");
  });

  it("returns null for an out-of-range row or a non-table position", () => {
    const state = stateOf(TABLE);
    expect(resolveCellRange(state, 0, 9, 0)).toBeNull();
    expect(resolveCellRange(stateOf("plain text"), 0, 0, 0)).toBeNull();
  });

  it("resolves a table that does not start at the document start", () => {
    const doc = `# heading\n\n${TABLE}`;
    const state = stateOf(doc);
    const tableFrom = doc.indexOf("| aa");
    const range = resolveCellRange(state, tableFrom, 1, 0);
    expect(state.sliceDoc(range!.from, range!.to)).toBe("cc");
  });
});

describe("escapeCell / unescapeCell", () => {
  it("round-trips arbitrary input", () => {
    for (const text of ["plain", "a|b", "a\\|b", "a\\\\|b", "trailing\\", "|", "\\", ""]) {
      expect(unescapeCell(escapeCell(text))).toBe(text);
    }
  });

  it("escapes pipes and backslashes in two stages", () => {
    expect(escapeCell("a|b")).toBe("a\\|b");
    expect(escapeCell("a\\|b")).toBe("a\\\\\\|b");
    expect(escapeCell("a\\")).toBe("a\\\\");
  });

  it("leaves other escape sequences untouched on unescape", () => {
    expect(unescapeCell("a\\*b")).toBe("a\\*b");
  });

  it("detects cells outside the round-trip domain (used for the raw-edit fallback)", () => {
    // Escapes other than \\ and \| would be rewritten on commit; the editor
    // falls back to raw editing for such cells.
    for (const raw of ["a\\*b", "a\\_b", "a\\"]) {
      expect(escapeCell(unescapeCell(raw))).not.toBe(raw);
    }
    for (const raw of ["plain", "a\\|b", "a\\\\b"]) {
      expect(escapeCell(unescapeCell(raw))).toBe(raw);
    }
  });
});

describe("countColumns", () => {
  it("counts columns with and without boundary pipes", () => {
    expect(countColumns(stateOf("| a | b |\n| --- | --- |"), 0)).toBe(2);
    expect(countColumns(stateOf("a | b\n--- | ---"), 0)).toBe(2);
    expect(countColumns(stateOf("| a |\n| --- |"), 0)).toBe(1);
  });

  it("counts an empty header cell", () => {
    expect(countColumns(stateOf("| a |  |\n| --- | --- |"), 0)).toBe(2);
  });
});

describe("nextCellLocation", () => {
  // 3 rows (incl. header) x 2 cols
  it("moves forward within a row, wraps to the next row, then appends", () => {
    expect(nextCellLocation(3, 2, 0, 0, "forward")).toEqual({ row: 0, col: 1 });
    expect(nextCellLocation(3, 2, 0, 1, "forward")).toEqual({ row: 1, col: 0 });
    expect(nextCellLocation(3, 2, 2, 1, "forward")).toBe("append");
  });

  it("moves backward within a row, wraps to the previous row, then stops", () => {
    expect(nextCellLocation(3, 2, 1, 1, "backward")).toEqual({ row: 1, col: 0 });
    expect(nextCellLocation(3, 2, 1, 0, "backward")).toEqual({ row: 0, col: 1 });
    expect(nextCellLocation(3, 2, 0, 0, "backward")).toBeNull();
  });

  it("moves down within a column and stops at the last row", () => {
    expect(nextCellLocation(3, 2, 0, 1, "down")).toEqual({ row: 1, col: 1 });
    expect(nextCellLocation(3, 2, 2, 1, "down")).toBeNull();
  });
});

describe("buildEmptyRowMarkdown", () => {
  it("builds piped empty rows", () => {
    expect(buildEmptyRowMarkdown(1)).toBe("|   |");
    expect(buildEmptyRowMarkdown(3)).toBe("|   |   |   |");
  });
});

describe("splitTableRow", () => {
  it("splits plain rows and strips boundary pipes", () => {
    expect(splitTableRow("| a | b |")).toEqual(["a", "b"]);
    expect(splitTableRow("a | b")).toEqual(["a", "b"]);
    expect(splitTableRow("| a |  | c |")).toEqual(["a", "", "c"]);
  });

  it("does not split on escaped pipes", () => {
    expect(splitTableRow("| a\\|b | c |")).toEqual(["a\\|b", "c"]);
  });

  it("splits on a pipe after an escaped backslash (lezer rule)", () => {
    expect(splitTableRow("| a\\\\| b |")).toEqual(["a\\\\", "b"]);
  });

  it("ignores trailing whitespace after the closing pipe", () => {
    expect(splitTableRow("| a | b |   ")).toEqual(["a", "b"]);
  });
});

describe("tableHasLinePrefix", () => {
  it("is false for top-level tables", () => {
    expect(tableHasLinePrefix(stateOf(TABLE), 0)).toBe(false);
  });

  it("is true for blockquoted tables", () => {
    const doc = "> | a | b |\n> | --- | --- |\n> | c | d |";
    const state = stateOf(doc);
    expect(tableHasLinePrefix(state, doc.indexOf("| a"))).toBe(true);
  });

  it("is true for indented tables", () => {
    const doc = "  | a | b |\n  | --- | --- |\n  | c | d |";
    const state = stateOf(doc);
    expect(tableHasLinePrefix(state, doc.indexOf("| a"))).toBe(true);
  });

  it("is true for tables inside list items", () => {
    const doc = "- item\n\n  | a | b |\n  | --- | --- |\n  | c | d |";
    const state = stateOf(doc);
    expect(tableHasLinePrefix(state, doc.indexOf("| a"))).toBe(true);
  });
});

describe("findTableByMarkdown", () => {
  it("returns the position of a unique occurrence", () => {
    const doc = `text\n\n${TABLE}`;
    expect(findTableByMarkdown(stateOf(doc), TABLE)).toBe(doc.indexOf("| aa"));
  });

  it("returns null when absent or ambiguous", () => {
    expect(findTableByMarkdown(stateOf("plain"), TABLE)).toBeNull();
    expect(findTableByMarkdown(stateOf(`${TABLE}\n\n${TABLE}`), TABLE)).toBeNull();
  });
});

describe("computeCellCommit", () => {
  it("replaces a cell's content extents", () => {
    const state = stateOf(TABLE);
    const changes = computeCellCommit(state, 0, 1, 0, "xx", "cc", "cc", false);
    expect(changes).toHaveLength(1);
    expect(applyChanges(state, changes!)).toBe(TABLE.replace("cc", "xx"));
  });

  it("writes into an empty cell with padding", () => {
    const state = stateOf(TABLE);
    const changes = computeCellCommit(state, 0, 1, 1, "xx", "", "", false);
    expect(applyChanges(state, changes!)).toContain("| cc | xx |");
  });

  it("clears a cell", () => {
    const state = stateOf(TABLE);
    const changes = computeCellCommit(state, 0, 1, 0, "", "cc", "cc", false);
    expect(applyChanges(state, changes!)).toContain("|  |  |");
  });

  it("keeps a pipe-less row alive when its only cell is cleared", () => {
    const doc = "| a |\n| --- |\nb\n| c |";
    const state = stateOf(doc);
    const changes = computeCellCommit(state, 0, 1, 0, "", "b", "b", false);
    const out = applyChanges(state, changes!);
    expect(out).toBe("| a |\n| --- |\n|\n| c |");
    // The following row must still belong to the table.
    const newState = stateOf(out);
    const range = resolveCellRange(newState, 0, 2, 0);
    expect(range).not.toBeNull();
    expect(newState.sliceDoc(range!.from, range!.to)).toBe("c");
  });

  it("returns [] for an unchanged value (input comparison, not doc slice)", () => {
    const state = stateOf(TABLE);
    expect(computeCellCommit(state, 0, 1, 0, "cc", "cc", "cc", false)).toEqual([]);
    // Escaped-whitespace cell: doc slice would differ from the trimmed raw,
    // but the input value is unchanged, so no rewrite happens.
    const escState = stateOf("| a\\ | b |\n| --- | --- |\n| c | d |");
    expect(computeCellCommit(escState, 0, 0, 0, "a\\", "a\\", "a\\", false)).toEqual([]);
  });

  it("aborts when the cell content is stale", () => {
    const state = stateOf(TABLE);
    expect(computeCellCommit(state, 0, 1, 0, "xx", "old", "old", false)).toBeNull();
  });

  it("aborts when the table cannot be resolved", () => {
    expect(computeCellCommit(stateOf("plain text"), 0, 0, 0, "xx", "old", "old", false)).toBeNull();
  });

  it("escapes pipes so the committed table keeps its structure", () => {
    const state = stateOf(TABLE);
    const changes = computeCellCommit(state, 0, 1, 0, "x|y", "cc", "cc", false);
    const out = applyChanges(state, changes!);
    const newState = stateOf(out);
    expect(countColumns(newState, 0)).toBe(2);
    const range = resolveCellRange(newState, 0, 1, 0);
    expect(unescapeCell(newState.sliceDoc(range!.from, range!.to).trim())).toBe("x|y");
  });

  it("escapes user-typed backslash-pipe without corrupting the table", () => {
    const state = stateOf(TABLE);
    const changes = computeCellCommit(state, 0, 1, 0, "x\\|y", "cc", "cc", false);
    const out = applyChanges(state, changes!);
    const newState = stateOf(out);
    expect(countColumns(newState, 0)).toBe(2);
    const range = resolveCellRange(newState, 0, 1, 0);
    expect(unescapeCell(newState.sliceDoc(range!.from, range!.to).trim())).toBe("x\\|y");
    // Sibling cell still resolves at the same slot.
    expect(resolveCellRange(newState, 0, 1, 1)).not.toBeNull();
  });

  it("keeps compact tables intact for values ending in a backslash", () => {
    const doc = "|a|b|\n|---|---|\n|c|d|";
    const state = stateOf(doc);
    const changes = computeCellCommit(state, 0, 1, 0, "x\\", "c", "c", false);
    const out = applyChanges(state, changes!);
    const newState = stateOf(out);
    expect(countColumns(newState, 0)).toBe(2);
    const second = resolveCellRange(newState, 0, 1, 1);
    expect(newState.sliceDoc(second!.from, second!.to)).toBe("d");
  });

  it("collapses newlines defensively", () => {
    const state = stateOf(TABLE);
    const changes = computeCellCommit(state, 0, 1, 0, "a\nb", "cc", "cc", false);
    expect(changes![0].insert).toBe("a b");
  });

  it("synthesizes missing pipes when committing into a ragged row", () => {
    const doc = "| a | b | c |\n| --- | --- | --- |\n| d |";
    const state = stateOf(doc);
    const changes = computeCellCommit(state, 0, 1, 2, "x", "", "", false);
    const out = applyChanges(state, changes!);
    const newState = stateOf(out);
    const range = resolveCellRange(newState, 0, 1, 2);
    expect(newState.sliceDoc(range!.from, range!.to)).toBe("x");
  });

  it("appends an empty row after the table", () => {
    const state = stateOf(TABLE);
    const changes = computeCellCommit(state, 0, 2, 1, "ff", "ee", "ee", true);
    expect(changes).toHaveLength(2);
    const out = applyChanges(state, changes!);
    expect(out.endsWith("| dd | ff |\n|   |   |")).toBe(true);
  });

  it("appends a row without a cell change when the value is unchanged", () => {
    const state = stateOf(TABLE);
    const changes = computeCellCommit(state, 0, 2, 1, "ee", "ee", "ee", true);
    expect(changes).toHaveLength(1);
    expect(applyChanges(state, changes!).endsWith("\n|   |   |")).toBe(true);
  });

  it("refuses to append a row to a prefixed (blockquoted) table", () => {
    const doc = "> | a | b |\n> | --- | --- |\n> | c | d |";
    const state = stateOf(doc);
    expect(computeCellCommit(state, doc.indexOf("| a"), 1, 0, "x", "c", "c", true)).toBeNull();
  });

  it("maps a later table's position across the commit changes", () => {
    const doc = `${TABLE}\n\n| xx | yy |\n| --- | --- |\n| zz | ww |`;
    const state = stateOf(doc);
    const changes = computeCellCommit(state, 0, 1, 0, "lengthened", "cc", "cc", false);
    const mapped = ChangeSet.of(changes!, state.doc.length).mapPos(doc.indexOf("| xx"), 1);
    expect(applyChanges(state, changes!).indexOf("| xx")).toBe(mapped);
  });
});
