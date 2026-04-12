import { foldEffect, foldedRanges, foldService, unfoldEffect } from "@codemirror/language";
import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { postToSwift } from "../bridge";

function headingFoldRange(state: EditorState, lineStart: number): { from: number; to: number } | null {
  const line = state.doc.lineAt(lineStart);
  const headingMatch = line.text.match(/^(#{1,6})\s/);
  if (!headingMatch) return null;

  const level = headingMatch[1].length;
  let endLine = state.doc.lines;

  for (let n = line.number + 1; n <= state.doc.lines; n++) {
    const next = state.doc.line(n);
    const nextMatch = next.text.match(/^(#{1,6})\s/);
    if (nextMatch && nextMatch[1].length <= level) {
      endLine = n - 1;
      break;
    }
  }

  return endLine > line.number ? { from: line.to, to: state.doc.line(endLine).to } : null;
}

function listFoldRange(state: EditorState, lineStart: number): { from: number; to: number } | null {
  const line = state.doc.lineAt(lineStart);
  const listMatch = line.text.match(/^(\s*)(?:[-*+]|\d+\.)\s/);
  if (!listMatch) return null;

  const indent = listMatch[1].length;
  let endLine = line.number;

  for (let n = line.number + 1; n <= state.doc.lines; n++) {
    const next = state.doc.line(n);
    if (next.text.trim() === "") continue;
    const nextIndent = next.text.match(/^(\s*)/)?.[1].length ?? 0;
    if (nextIndent <= indent) break;
    endLine = n;
  }

  return endLine > line.number ? { from: line.to, to: state.doc.line(endLine).to } : null;
}

export const markdownHeadingFold = foldService.of(headingFoldRange);
export const markdownListFold = foldService.of(listFoldRange);

// Track last folded state to avoid duplicate notifications across rapid updates
let lastFoldedKey = "";

export const foldChangeListener = EditorView.updateListener.of((update) => {
  // Skip if no fold/unfold effects were applied — covers ~99% of keystrokes/cursor moves
  const hasFoldEffect = update.transactions.some((tr) =>
    tr.effects.some((e) => e.is(foldEffect) || e.is(unfoldEffect))
  );
  if (!hasFoldEffect) return;

  const foldedLines: number[] = [];
  foldedRanges(update.state).between(0, update.state.doc.length, (from) => {
    foldedLines.push(update.state.doc.lineAt(from).number);
  });

  const key = foldedLines.join(",");
  if (key === lastFoldedKey) return;
  lastFoldedKey = key;

  postToSwift({ type: "foldChanged", foldedLines });
});

function computeFoldRange(
  state: EditorState,
  lineNum: number,
): { from: number; to: number } | null {
  if (lineNum < 1 || lineNum > state.doc.lines) return null;
  const lineFrom = state.doc.line(lineNum).from;
  return headingFoldRange(state, lineFrom) ?? listFoldRange(state, lineFrom);
}

export function applyFoldingFromLines(view: EditorView, lines: number[]) {
  const effects = [];
  for (const lineNum of lines) {
    const range = computeFoldRange(view.state, lineNum);
    if (range) {
      effects.push(foldEffect.of(range));
    }
  }
  if (effects.length > 0) {
    view.dispatch({ effects });
    lastFoldedKey = [...lines].sort((a, b) => a - b).join(",");
  }
}
