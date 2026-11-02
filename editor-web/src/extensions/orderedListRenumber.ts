// Keeps ordered list numbers sequential after edits inside the editor.
//
// Chirami shows list numbers as written, so deleting, moving, cutting or
// pasting items leaves visible gaps ("2. 3. 5."). CodeMirror only renumbers
// on Enter. This filter appends the renumbering to the same transaction, so
// one undo reverts both.
//
// Scope (deliberately narrow):
// - only lists touched by the edit;
// - not for external file updates, undo/redo, or IME composition;
// - lists written with one repeated number ("1. 1. 1.") are left alone;
// - the first number is kept: if the user edited the first marker, its new
//   value wins; otherwise the list keeps the start it had before the edit
//   (deleting "1. a" turns "2. b / 3. c" into "1. b / 2. c").

import { ensureSyntaxTree, syntaxTree } from "@codemirror/language";
import { ChangeSpec, EditorState, Transaction, TransactionSpec } from "@codemirror/state";
import type { SyntaxNode, Tree } from "@lezer/common";

interface Marker {
  from: number;
  to: number;
  number: number;
  delimiter: string;
}

function markersOf(state: EditorState, list: SyntaxNode): Marker[] {
  const out: Marker[] = [];
  for (let item = list.firstChild; item; item = item.nextSibling) {
    if (item.name !== "ListItem") continue;
    const mark = item.getChild("ListMark");
    if (!mark) continue;
    const text = state.sliceDoc(mark.from, mark.to);
    const number = parseInt(text, 10);
    if (Number.isNaN(number)) continue;
    out.push({ from: mark.from, to: mark.to, number, delimiter: text.slice(-1) });
  }
  return out;
}

function orderedListAt(tree: Tree, pos: number): SyntaxNode | null {
  for (const side of [1, -1] as const) {
    for (let n: SyntaxNode | null = tree.resolveInner(pos, side); n; n = n.parent) {
      if (n.name === "OrderedList") return n;
    }
  }
  return null;
}

function treeOf(state: EditorState): Tree {
  return ensureSyntaxTree(state, state.doc.length, 100) ?? syntaxTree(state);
}

/** Renumbering changes for `tr` (positions in tr.state.doc), or null. */
export function renumberChanges(tr: Transaction): ChangeSpec[] | null {
  if (!tr.docChanged) return null;
  if (
    tr.isUserEvent("external") ||
    tr.isUserEvent("undo") ||
    tr.isUserEvent("redo") ||
    tr.isUserEvent("input.type.compose")
  ) {
    return null;
  }

  const state = tr.state;
  const tree = treeOf(state);
  const ranges: { from: number; to: number }[] = [];
  tr.changes.iterChangedRanges((_fromA, _toA, fromB, toB) => ranges.push({ from: fromB, to: toB }));

  const lists = new Map<number, SyntaxNode>();
  for (const r of ranges) {
    tree.iterate({
      from: Math.max(0, r.from - 1),
      to: Math.min(state.doc.length, r.to + 1),
      enter: (n) => {
        if (n.name === "OrderedList") lists.set(n.from, n.node);
      },
    });
  }
  if (lists.size === 0) return null;

  const oldTree = treeOf(tr.startState);
  const changes: ChangeSpec[] = [];
  for (const list of lists.values()) {
    const marks = markersOf(state, list);
    if (marks.length < 2) continue;
    if (marks.every((m) => m.number === marks[0].number)) continue;

    const first = marks[0];
    const editedFirst = ranges.some((r) =>
      r.to > r.from ? r.from < first.to && r.to > first.from : r.from > first.from && r.from < first.to,
    );
    let start = first.number;
    if (!editedFirst) {
      const oldList = orderedListAt(oldTree, tr.changes.invertedDesc.mapPos(list.from, 1));
      const oldMarks = oldList ? markersOf(tr.startState, oldList) : [];
      if (oldMarks.length > 0) start = oldMarks[0].number;
    }

    marks.forEach((m, i) => {
      const expected = start + i;
      if (m.number !== expected) {
        changes.push({ from: m.from, to: m.to, insert: `${expected}${m.delimiter}` });
      }
    });
  }
  return changes.length > 0 ? changes : null;
}

export const orderedListRenumber = EditorState.transactionFilter.of((tr): Transaction | readonly (Transaction | TransactionSpec)[] => {
  const changes = renumberChanges(tr);
  if (!changes) return tr;
  return [tr, { changes, sequential: true }];
});
