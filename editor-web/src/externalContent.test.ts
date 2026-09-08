import { describe, expect, it } from "vitest";
import { EditorState, Transaction } from "@codemirror/state";
import { externalContentTransaction } from "./externalContent";

function update(doc: string, text: string, anchor: number, head = anchor) {
  const state = EditorState.create({ doc, selection: { anchor, head } });
  return state.update(externalContentTransaction(state, text));
}

describe("external content selection", () => {
  it("follows unchanged text when lines are inserted above the caret", () => {
    const tr = update("one\ntwo\nthree", "new\none\ntwo\nthree", 6);
    expect(tr.state.selection.main.head).toBe(10);
    expect(tr.state.doc.toString()).toBe("new\none\ntwo\nthree");
    expect(tr.annotation(Transaction.addToHistory)).toBe(false);
    expect(tr.isUserEvent("external")).toBe(true);
  });

  it("follows unchanged text when preceding lines are removed", () => {
    expect(update("one\ntwo\nthree", "two\nthree", 6).state.selection.main.head).toBe(2);
  });

  it("leaves the caret in place for edits after it or identical content", () => {
    expect(update("one\ntwo", "one\nchanged", 2).state.selection.main.head).toBe(2);
    expect(update("one\ntwo", "one\ntwo", 5).state.selection.main.head).toBe(5);
  });

  it("preserves the relative line and column within rewritten text", () => {
    expect(update("aaa\nbbbbb\nccc", "xxx\nyyyyy\nzzz", 7).state.selection.main.head).toBe(7);
    expect(update("aaa\nbbbbb\nccc", "xxx\ny\nzzz", 8).state.selection.main.head).toBe(5);
  });

  it("clamps positions when the current line or whole document disappears", () => {
    expect(update("aaa\nbbbbb\nccc", "x", 8).state.selection.main.head).toBe(1);
    expect(update("aaa\nbbbbb\nccc", "", 8).state.selection.main.head).toBe(0);
  });

  it("preserves selection direction and both endpoints", () => {
    const selection = update("one\ntwo\nthree", "new\none\ntwo\nthree", 7, 4).state.selection.main;
    expect([selection.anchor, selection.head]).toEqual([11, 8]);
  });

  it("uses CodeMirror positions for CRLF and Japanese text", () => {
    const tr = update("あいう\nかきく", "追加\r\nあいう\r\nかきく", 5);
    expect(tr.state.selection.main.head).toBe(8);
    expect(tr.state.doc.toString()).toBe("追加\nあいう\nかきく");
  });
});
