import { describe, expect, it } from "vitest";
import { EditorState, Transaction } from "@codemirror/state";
import {
  cursorInSpan,
  cursorLineFromState,
  cursorRevealField,
  parseCodeBlockInfo,
  setWindowActiveEffect,
  sizeOptionsEq,
  transactionCursorRevealChanged,
  tryParseJSON,
  windowActiveField,
} from "./utils";

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

describe("cursorRevealField", () => {
  function createState(doc = "# Heading\n\nBody"): EditorState {
    return EditorState.create({
      doc,
      extensions: [windowActiveField, cursorRevealField],
    });
  }

  it("starts unrevealed so cursorLineFromState hides the cursor line", () => {
    const state = createState();
    expect(state.field(cursorRevealField)).toBe(false);
    expect(cursorLineFromState(state)).toBe(-1);
  });

  it("does not reveal on external content replacement", () => {
    const state = createState();
    const tr = state.update({
      changes: { from: 0, to: state.doc.length, insert: "# New" },
      annotations: Transaction.userEvent.of("external"),
    });
    expect(tr.state.field(cursorRevealField)).toBe(false);
  });

  it("does not reveal on programmatic cursor restore (no user event)", () => {
    const state = createState();
    const tr = state.update({ selection: { anchor: 3 } });
    expect(tr.state.field(cursorRevealField)).toBe(false);
  });

  it("does not reveal on a synthetic compose flush without changes", () => {
    const state = createState();
    const tr = state.update({
      annotations: Transaction.userEvent.of("input.compose.flush"),
    });
    expect(tr.state.field(cursorRevealField)).toBe(false);
  });

  it("reveals on pointer selection and reports the cursor line", () => {
    const state = createState();
    const tr = state.update({
      selection: { anchor: 2 },
      annotations: Transaction.userEvent.of("select.pointer"),
    });
    expect(tr.state.field(cursorRevealField)).toBe(true);
    expect(transactionCursorRevealChanged(tr)).toBe(true);
    expect(cursorLineFromState(tr.state)).toBe(1);
  });

  it("reveals on typing input", () => {
    const state = createState();
    const tr = state.update({
      changes: { from: 0, insert: "a" },
      annotations: Transaction.userEvent.of("input.type"),
    });
    expect(tr.state.field(cursorRevealField)).toBe(true);
  });

  it("resets when the window becomes inactive", () => {
    const revealed = createState().update({
      selection: { anchor: 2 },
      annotations: Transaction.userEvent.of("select.pointer"),
    }).state;
    const tr = revealed.update({
      effects: setWindowActiveEffect.of(false),
    });
    expect(tr.state.field(cursorRevealField)).toBe(false);
    expect(transactionCursorRevealChanged(tr)).toBe(true);
  });

  it("stays revealed while the window remains active", () => {
    const revealed = createState().update({
      selection: { anchor: 2 },
      annotations: Transaction.userEvent.of("select.pointer"),
    }).state;
    const tr = revealed.update({
      changes: { from: 0, to: revealed.doc.length, insert: "# Reload" },
      annotations: Transaction.userEvent.of("external"),
    });
    expect(tr.state.field(cursorRevealField)).toBe(true);
  });

  it("defaults to revealed when the field is not registered", () => {
    const state = EditorState.create({ doc: "# H", extensions: [windowActiveField] });
    expect(cursorLineFromState(state)).toBe(1);
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
