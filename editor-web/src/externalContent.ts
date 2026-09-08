import { EditorSelection, EditorState, Transaction, type TransactionSpec } from "@codemirror/state";

// Keep positions in unchanged text attached to that text. Within rewritten
// text, fall back to the same relative line and column, clamped to its bounds.
export function externalContentTransaction(state: EditorState, text: string): TransactionSpec {
  const next = state.toText(text);
  const before = state.doc.toString();
  const after = next.toString();
  let from = 0;
  while (from < before.length && from < after.length && before[from] === after[from]) from++;
  let oldEnd = before.length;
  let newEnd = after.length;
  while (oldEnd > from && newEnd > from && before[oldEnd - 1] === after[newEnd - 1]) {
    oldEnd--;
    newEnd--;
  }

  const mapPosition = (pos: number) => {
    if (pos <= from) return pos;
    if (pos >= oldEnd) return pos + newEnd - oldEnd;
    const line = state.doc.lineAt(pos);
    const targetLine = Math.min(
      next.lineAt(from).number + line.number - state.doc.lineAt(from).number,
      next.lineAt(newEnd).number,
    );
    const target = next.line(targetLine);
    return Math.max(from, Math.min(newEnd, target.to, target.from + pos - line.from));
  };

  return {
    changes: { from: 0, to: state.doc.length, insert: next },
    selection: EditorSelection.create(state.selection.ranges.map(range =>
      EditorSelection.range(mapPosition(range.anchor), mapPosition(range.head)),
    ), state.selection.mainIndex),
    annotations: [Transaction.userEvent.of("external"), Transaction.addToHistory.of(false)],
  };
}
