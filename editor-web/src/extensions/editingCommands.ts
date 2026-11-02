// Keyboard editing commands tuned for keyboard-only (Emacs-style) use:
// list subtree indent/dedent, smart line start, kill-to-clipboard, CJK word
// motion, raw-table cell navigation and vertical moves into block widgets.

import { foldedRanges, syntaxTree } from "@codemirror/language";
import { ChangeSpec, EditorSelection, EditorState, Line, SelectionRange } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import type { SyntaxNode } from "@lezer/common";
import { postToSwift } from "../bridge";
import { indentWidth, leadingWhitespace, ListLine, listLineAt, subtreeEnd } from "./listContext";

// ---------------------------------------------------------------------------
// List indent / dedent

/** Nearest earlier list item at exactly `width`, stopping at a shallower line. */
function previousSiblingAt(state: EditorState, lineNumber: number, width: number): ListLine | null {
  for (let n = lineNumber - 1; n >= 1; n--) {
    const line = state.doc.line(n);
    if (line.text.trim() === "") continue;
    const w = indentWidth(leadingWhitespace(line.text), state.tabSize);
    const item = listLineAt(state, line);
    if (w < width) return null;
    if (w === width && item) return item;
  }
  return null;
}

/** Nearest earlier list item shallower than `width` (the parent item). */
function parentItem(state: EditorState, lineNumber: number, width: number): ListLine | null {
  for (let n = lineNumber - 1; n >= 1; n--) {
    const line = state.doc.line(n);
    if (line.text.trim() === "") continue;
    const item = listLineAt(state, line);
    const w = indentWidth(leadingWhitespace(line.text), state.tabSize);
    if (item && w < width) return item;
    if (!item && w === 0) return null;
  }
  return null;
}

/** Indentation the item would get one level deeper. */
function deeperIndent(state: EditorState, item: ListLine): string {
  // Space-indented lists (pasted from GitHub etc.) nest at the parent's
  // content column; adding a tab there would mix tabs and spaces.
  if (item.indent.includes(" ")) {
    const width = indentWidth(item.indent, state.tabSize);
    const sibling = previousSiblingAt(state, item.line.number, width);
    const step = sibling ? sibling.marker.length + 1 : item.marker.length + 1;
    return item.indent + " ".repeat(step);
  }
  return "\t" + item.indent;
}

/** Indentation the item would get one level shallower, or null at top level. */
function shallowerIndent(state: EditorState, item: ListLine): string | null {
  const width = indentWidth(item.indent, state.tabSize);
  if (width === 0) return null;
  const parent = parentItem(state, item.line.number, width);
  return parent ? parent.indent : "";
}

/** New marker for an ordered item moved to `indent` (continues the siblings there). */
function renumberedMarker(state: EditorState, item: ListLine, indent: string): string | null {
  if (!item.ordered) return null;
  const delimiter = item.marker.slice(-1);
  const sibling = previousSiblingAt(state, item.line.number, indentWidth(indent, state.tabSize));
  const next = sibling?.ordered ? parseInt(sibling.marker, 10) + 1 : 1;
  const marker = `${next}${delimiter}`;
  return marker === item.marker ? null : marker;
}

/** Changes that move the lines [from, to] from `oldIndent` to `newIndent`. */
function reindentLines(state: EditorState, from: number, to: number, oldIndent: string, newIndent: string): ChangeSpec[] {
  const changes: ChangeSpec[] = [];
  for (let n = from; n <= to; n++) {
    const line = state.doc.line(n);
    if (line.text.trim() === "") continue;
    const ws = leadingWhitespace(line.text);
    if (ws.startsWith(oldIndent)) {
      changes.push({ from: line.from, to: line.from + oldIndent.length, insert: newIndent });
    } else {
      // Shallower continuation line inside the subtree: shift by the width delta.
      const delta = indentWidth(newIndent, state.tabSize) - indentWidth(oldIndent, state.tabSize);
      if (delta > 0) changes.push({ from: line.from, insert: newIndent.startsWith("\t") ? "\t" : " ".repeat(delta) });
    }
  }
  return changes;
}

function moveListItem(view: EditorView, deeper: boolean): boolean {
  const { state } = view;
  const sel = state.selection.main;
  if (!sel.empty) return moveSelectedLines(view, deeper);

  const item = listLineAt(state, state.doc.lineAt(sel.head));
  if (!item) return false;
  const newIndent = deeper ? deeperIndent(state, item) : shallowerIndent(state, item);
  if (newIndent === null) return false;

  const end = subtreeEnd(state, item.line.number);
  const changes = reindentLines(state, item.line.number, end, item.indent, newIndent);
  const marker = renumberedMarker(state, item, newIndent);
  const markFrom = item.line.from + item.indent.length;
  if (marker) changes.push({ from: markFrom, to: markFrom + item.marker.length, insert: marker });

  const changeSet = state.changes(changes);
  const keepAtContent = sel.head < item.contentStart || item.contentStart >= item.line.to;
  const head = keepAtContent ? changeSet.mapPos(item.contentStart, 1) : changeSet.mapPos(sel.head, 1);
  view.dispatch({ changes: changeSet, selection: EditorSelection.cursor(head), scrollIntoView: true, userEvent: "input.indent" });
  return true;
}

/** Selected line numbers; a selection ending at column 0 excludes that line. */
function selectedLineRange(state: EditorState, range: SelectionRange): [number, number] {
  const first = state.doc.lineAt(range.from).number;
  let last = state.doc.lineAt(range.to).number;
  if (last > first && state.doc.line(last).from === range.to) last--;
  return [first, last];
}

function moveSelectedLines(view: EditorView, deeper: boolean): boolean {
  const { state } = view;
  const [first, last] = selectedLineRange(state, state.selection.main);
  const changes: ChangeSpec[] = [];
  for (let n = first; n <= last; n++) {
    const line = state.doc.line(n);
    if (line.text.trim() === "") continue;
    const item = listLineAt(state, line);
    if (item) {
      const newIndent = deeper ? deeperIndent(state, item) : shallowerIndent(state, item);
      if (newIndent === null) continue;
      changes.push({ from: line.from, to: line.from + item.indent.length, insert: newIndent });
      const marker = renumberedMarker(state, item, newIndent);
      const markFrom = line.from + item.indent.length;
      if (marker) changes.push({ from: markFrom, to: markFrom + item.marker.length, insert: marker });
      continue;
    }
    const ws = leadingWhitespace(line.text);
    if (deeper) {
      changes.push({ from: line.from, insert: "\t" });
    } else if (ws.length > 0) {
      const remove = ws.startsWith("\t") ? 1 : Math.min(ws.length, state.tabSize);
      changes.push({ from: line.from, to: line.from + remove });
    }
  }
  if (changes.length === 0) return true;
  const changeSet = state.changes(changes);
  // A selection edge at column 0 stays at column 0 (whole-line selections stay whole).
  const map = (pos: number) => (state.doc.lineAt(pos).from === pos ? changeSet.mapPos(pos, -1) : changeSet.mapPos(pos, 1));
  const range = state.selection.main;
  view.dispatch({
    changes: changeSet,
    selection: EditorSelection.range(map(range.anchor), map(range.head)),
    scrollIntoView: true,
    userEvent: "input.indent",
  });
  return true;
}

export const indentListItem = (view: EditorView) => moveListItem(view, true);
export const dedentListItem = (view: EditorView) => moveListItem(view, false);

// ---------------------------------------------------------------------------
// Smart line start (Ctrl-A)

const PREFIX_MARKS = new Set(["QuoteMark", "HeaderMark"]);

/** Position where the text of the line starts, after list / quote / heading markup. */
export function lineContentStart(state: EditorState, line: Line): number {
  const item = listLineAt(state, line);
  if (item) return item.contentStart;
  let pos = line.from;
  const skipSpaces = () => {
    while (pos < line.to && (line.text[pos - line.from] === " " || line.text[pos - line.from] === "\t")) pos++;
  };
  skipSpaces();
  let advanced = true;
  while (advanced && pos < line.to) {
    advanced = false;
    syntaxTree(state).iterate({
      from: pos,
      to: Math.min(pos + 1, line.to),
      enter: (node) => {
        if (!advanced && PREFIX_MARKS.has(node.name) && node.from === pos) {
          pos = node.to;
          advanced = true;
        }
      },
    });
    if (advanced) {
      skipSpaces();
      const nested = listLineAt(state, line);
      if (nested && nested.contentStart > pos) pos = nested.contentStart;
    }
  }
  return pos;
}

function smartLineStart(view: EditorView, extend: boolean): boolean {
  const { state } = view;
  const sel = state.selection.main;
  const line = state.doc.lineAt(sel.head);
  const content = lineContentStart(state, line);
  // First press jumps to the text; pressing again at the text goes to column 0.
  const target = sel.head === content || content === line.to ? line.from : content;
  view.dispatch({
    selection: extend ? EditorSelection.range(sel.anchor, target) : EditorSelection.cursor(target),
    scrollIntoView: true,
    userEvent: "select",
  });
  return true;
}

export const cursorSmartLineStart = (view: EditorView) => smartLineStart(view, false);
export const selectSmartLineStart = (view: EditorView) => smartLineStart(view, true);

// ---------------------------------------------------------------------------
// Kill to clipboard (Ctrl-K)

let lastKill: { doc: EditorState["doc"]; pos: number; text: string } | null = null;

/** Writes text to the system clipboard from inside a key handler (user gesture). */
export function writeClipboard(text: string): boolean {
  let written = false;
  const onCopy = (e: ClipboardEvent) => {
    e.clipboardData?.setData("text/plain", text);
    e.preventDefault();
    written = true;
  };
  document.addEventListener("copy", onCopy, true);
  try {
    document.execCommand("copy");
  } finally {
    document.removeEventListener("copy", onCopy, true);
  }
  if (written) return true;

  // WebKit only runs the copy command with a non-empty selection: copy from a
  // throwaway textarea, then give focus back to the editor.
  const active = document.activeElement as HTMLElement | null;
  const area = document.createElement("textarea");
  area.value = text;
  area.setAttribute("readonly", "");
  area.style.position = "fixed";
  area.style.opacity = "0";
  document.body.appendChild(area);
  area.select();
  try {
    written = document.execCommand("copy");
  } finally {
    area.remove();
    active?.focus({ preventScroll: true });
  }
  if (!written) postToSwift({ type: "log", level: "warn", message: "killLine: clipboard write failed" });
  return written;
}

/**
 * Emacs kill-line: delete to the end of the line (or the line break at the
 * end) and put the killed text on the clipboard, so Ctrl-Y (Cmd-V through
 * Karabiner) yanks it back. Consecutive kills accumulate like Emacs.
 */
export function killLine(view: EditorView): boolean {
  const { state } = view;
  const sel = state.selection.main;
  if (!sel.empty) return false;
  const line = state.doc.lineAt(sel.head);
  const to = sel.head < line.to ? line.to : Math.min(line.to + 1, state.doc.length);
  if (to === sel.head) return true;
  const killed = state.sliceDoc(sel.head, to);
  const append = lastKill !== null && lastKill.doc === state.doc && lastKill.pos === sel.head;
  const text = append && lastKill ? lastKill.text + killed : killed;
  view.dispatch({ changes: { from: sel.head, to }, userEvent: "delete.cut", scrollIntoView: true });
  lastKill = { doc: view.state.doc, pos: sel.head, text };
  writeClipboard(text);
  return true;
}

// ---------------------------------------------------------------------------
// Blockquote: Enter on an empty quote line leaves the quote

/** If the line holds only quote markers, returns the position of the last one. */
function emptyQuoteLastMark(state: EditorState, line: Line): number | null {
  if (line.text.trim() === "") return null;
  for (const ch of line.text) {
    if (ch !== ">" && ch !== " " && ch !== "\t") return null;
  }
  // The ">" characters must be real quote markers (not text inside code).
  let last: number | null = null;
  syntaxTree(state).iterate({
    from: line.from,
    to: line.to,
    enter: (node) => {
      if (node.name === "QuoteMark" && node.from >= line.from) last = node.from;
    },
  });
  return last;
}

export function exitEmptyQuote(view: EditorView): boolean {
  const { state } = view;
  const sel = state.selection.main;
  if (!sel.empty) return false;
  const line = state.doc.lineAt(sel.head);
  if (sel.head !== line.to) return false;
  const lastMark = emptyQuoteLastMark(state, line);
  if (lastMark === null) return false;
  // Drop the innermost level; a single level becomes an empty line.
  const outer = state.sliceDoc(line.from, lastMark);
  const from = outer.trim() === "" ? line.from : lastMark;
  // Keep a space after the remaining outer marker so typing continues as "> text".
  const insert = from === line.from || outer.endsWith(" ") ? "" : " ";
  view.dispatch({
    changes: { from, to: line.to, insert },
    selection: EditorSelection.cursor(from + insert.length),
    userEvent: "delete",
    scrollIntoView: true,
  });
  return true;
}

// ---------------------------------------------------------------------------
// Shift-Enter: line break inside a list item

export function listSoftBreak(view: EditorView): boolean {
  const { state } = view;
  const sel = state.selection.main;
  const item = listLineAt(state, state.doc.lineAt(sel.head));
  if (!item) return false;
  const insert = state.lineBreak + item.indent + " ".repeat(item.marker.length + 1);
  view.dispatch(state.update(state.replaceSelection(insert), { scrollIntoView: true, userEvent: "input" }));
  return true;
}

// ---------------------------------------------------------------------------
// CJK word motion (Option-Left / Option-Right)

const CJK_RE = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}ー々]/u;
const segmenter = typeof Intl !== "undefined" && "Segmenter" in Intl
  ? new Intl.Segmenter("ja", { granularity: "word" })
  : null;

/**
 * CodeMirror groups every CJK character into one "word", so Option-Right jumps
 * a whole Japanese sentence. Use the ICU word segmenter instead when the
 * character in the direction of travel is CJK; otherwise defer to the default.
 */
function cjkWordMove(view: EditorView, forward: boolean, extend: boolean): boolean {
  if (!segmenter) return false;
  const { state } = view;
  const sel = state.selection.main;
  const line = state.doc.lineAt(sel.head);
  const offset = sel.head - line.from;
  const ch = forward ? line.text[offset] : line.text[offset - 1];
  if (!ch || !CJK_RE.test(ch)) return false;

  // Like the macOS text system: skip punctuation/spaces, stop at the far edge
  // of the next word-like segment (or the line edge).
  const segments = Array.from(segmenter.segment(line.text));
  let target = forward ? line.to : line.from;
  if (forward) {
    const next = segments.find((s) => s.index + s.segment.length > offset && s.isWordLike);
    if (next) target = line.from + next.index + next.segment.length;
  } else {
    const prev = [...segments].reverse().find((s) => s.index < offset && s.isWordLike);
    if (prev) target = line.from + prev.index;
  }
  if (target === sel.head) return false;
  view.dispatch({
    selection: extend ? EditorSelection.range(sel.anchor, target) : EditorSelection.cursor(target),
    scrollIntoView: true,
    userEvent: "select",
  });
  return true;
}

export const cursorCjkWordRight = (view: EditorView) => cjkWordMove(view, true, false);
export const cursorCjkWordLeft = (view: EditorView) => cjkWordMove(view, false, false);
export const selectCjkWordRight = (view: EditorView) => cjkWordMove(view, true, true);
export const selectCjkWordLeft = (view: EditorView) => cjkWordMove(view, false, true);

// ---------------------------------------------------------------------------
// Raw table: Tab / Shift-Tab move between cells

function tableAt(state: EditorState, pos: number): SyntaxNode | null {
  // Check both sides so the cursor at column 0 (before the first pipe) counts.
  for (const side of [-1, 1] as const) {
    for (let n: SyntaxNode | null = syntaxTree(state).resolveInner(pos, side); n; n = n.parent) {
      if (n.name === "Table") return n;
    }
  }
  return null;
}

/** Start positions of every editable cell in the table, in document order. */
function tableCellStarts(state: EditorState, table: SyntaxNode): number[] {
  const starts: number[] = [];
  for (let row = table.firstChild; row; row = row.nextSibling) {
    if (row.name !== "TableHeader" && row.name !== "TableRow") continue;
    const line = state.doc.lineAt(row.from);
    const pipes: number[] = [];
    for (let c = row.firstChild; c; c = c.nextSibling) {
      if (c.name === "TableDelimiter") pipes.push(c.from);
    }
    // A cell starts after each pipe that is not the closing one at line end.
    for (const p of pipes) {
      if (state.sliceDoc(p + 1, line.to).trim() === "") continue;
      let s = p + 1;
      if (state.sliceDoc(s, s + 1) === " ") s++;
      starts.push(s);
    }
    // Rows without a leading pipe start at the line's text.
    if (pipes.length === 0 || pipes[0] > line.from + leadingWhitespace(line.text).length) {
      starts.push(line.from + leadingWhitespace(line.text).length);
      starts.sort((a, b) => a - b);
    }
  }
  return starts;
}

function moveTableCell(view: EditorView, forward: boolean): boolean {
  const { state } = view;
  const sel = state.selection.main;
  const table = tableAt(state, sel.head);
  if (!table) return false;
  const starts = tableCellStarts(state, table);
  // Backward skips the cell the cursor is in and goes to the previous one.
  const current = [...starts].reverse().find((s) => s <= sel.head);
  const target = forward
    ? starts.find((s) => s > sel.head)
    : [...starts].reverse().find((s) => s < (current ?? sel.head));
  if (target === undefined) {
    if (forward) appendTableRow(view, table);
    return true;
  }
  view.dispatch({ selection: EditorSelection.cursor(target), scrollIntoView: true, userEvent: "select" });
  return true;
}

/** Tab on the last cell appends an empty row (same as the cell editor) and moves into it. */
function appendTableRow(view: EditorView, table: SyntaxNode): void {
  const { state } = view;
  let header: SyntaxNode | null = null;
  let lastRow: SyntaxNode | null = null;
  for (let row = table.firstChild; row; row = row.nextSibling) {
    if (row.name === "TableHeader") header = row;
    if (row.name === "TableHeader" || row.name === "TableRow" || row.name === "TableDelimiter") lastRow = row;
  }
  if (!header || !lastRow) return;
  const headerLine = state.doc.lineAt(header.from);
  let pipes = 0;
  for (let c = header.firstChild; c; c = c.nextSibling) {
    if (c.name === "TableDelimiter") pipes++;
  }
  const leading = headerLine.text.trimStart().startsWith("|");
  const trailing = headerLine.text.trimEnd().endsWith("|");
  const columns = Math.max(1, pipes - (leading ? 1 : 0) - (trailing ? 1 : 0) + 1);
  const row = "| " + Array(columns).fill("").join(" | ") + " |";
  const end = state.doc.lineAt(lastRow.to).to;
  view.dispatch({
    changes: { from: end, insert: state.lineBreak + row },
    selection: EditorSelection.cursor(end + state.lineBreak.length + 2),
    scrollIntoView: true,
    userEvent: "input",
  });
}

export const nextTableCell = (view: EditorView) => moveTableCell(view, true);
export const previousTableCell = (view: EditorView) => moveTableCell(view, false);

// ---------------------------------------------------------------------------
// Moving up into a block widget

/**
 * Rendered blocks (tables, Mermaid) replace several lines with one widget, and
 * moving up from below lands on the widget's first line. Stop on the line just
 * above instead, like moving down does; the block then reveals its source.
 */
function lineUpIntoBlock(view: EditorView, extend: boolean): boolean {
  const { state } = view;
  const sel = state.selection.main;
  if (!extend && !sel.empty) return false;
  const line = state.doc.lineAt(sel.head);
  if (line.number === 1) return false;
  const moved = view.moveVertically(sel, false);
  const landed = state.doc.lineAt(moved.head).number;
  if (landed >= line.number - 1) return false;

  const above = state.doc.line(line.number - 1);
  let folded = false;
  foldedRanges(state).between(state.doc.line(landed).from, above.to, () => {
    folded = true;
  });
  if (folded) return false;

  const target = above.from + Math.min(sel.head - line.from, above.length);
  view.dispatch({
    selection: extend ? EditorSelection.range(sel.anchor, target) : EditorSelection.cursor(target),
    scrollIntoView: true,
    userEvent: "select",
  });
  return true;
}

export const cursorLineUpIntoBlock = (view: EditorView) => lineUpIntoBlock(view, false);
export const selectLineUpIntoBlock = (view: EditorView) => lineUpIntoBlock(view, true);

// ---------------------------------------------------------------------------
// Option-Up / Option-Down: move a list item together with its children

/**
 * Swaps the list item at the cursor (with its subtree) with the previous or
 * next sibling item (with its subtree). CodeMirror's moveLine moves only the
 * cursor line, leaving the children behind under a different parent.
 * At the first/last sibling it does nothing, so the structure never breaks.
 */
function moveListSubtree(view: EditorView, up: boolean): boolean {
  const { state } = view;
  const sel = state.selection.main;
  const line = state.doc.lineAt(sel.head);
  const item = listLineAt(state, line);
  if (!item) return false;
  if (!sel.empty && state.doc.lineAt(sel.anchor).number !== line.number) return false;

  const width = indentWidth(item.indent, state.tabSize);
  const start = line.number;
  const end = subtreeEnd(state, start);

  let aStart: number;
  let bStart: number;
  let bEnd: number;
  if (up) {
    const prev = previousSiblingAt(state, start, width);
    if (!prev) return true;
    aStart = prev.line.number;
    bStart = start;
    bEnd = end;
  } else {
    let next = end + 1;
    while (next <= state.doc.lines && state.doc.line(next).text.trim() === "") next++;
    if (next > state.doc.lines) return true;
    const nextItem = listLineAt(state, state.doc.line(next));
    if (!nextItem || indentWidth(nextItem.indent, state.tabSize) !== width) return true;
    aStart = start;
    bStart = next;
    bEnd = subtreeEnd(state, next);
  }
  // Keep blank lines between the blocks with the block above them.
  const from = state.doc.line(aStart).from;
  const mid = state.doc.line(bStart).from;
  const to = state.doc.line(bEnd).to;
  const blockA = state.sliceDoc(from, mid - 1);
  const blockB = state.sliceDoc(mid, to);
  const insert = blockB + state.lineBreak + blockA;

  // The moved item is block B when going up, block A when going down.
  const offsetInItem = sel.head - line.from;
  const anchorOffset = sel.anchor - line.from;
  const newLineFrom = up ? from : from + blockB.length + state.lineBreak.length + (line.from - from);
  view.dispatch({
    changes: { from, to, insert },
    selection: EditorSelection.range(newLineFrom + anchorOffset, newLineFrom + offsetInItem),
    scrollIntoView: true,
    userEvent: "move.line",
  });
  return true;
}

export const moveListItemUp = (view: EditorView) => moveListSubtree(view, true);
export const moveListItemDown = (view: EditorView) => moveListSubtree(view, false);
