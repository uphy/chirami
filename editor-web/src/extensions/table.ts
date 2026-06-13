import { syntaxTree } from "@codemirror/language";
import { ChangeSet, EditorState, Range } from "@codemirror/state";
import { isolateHistory } from "@codemirror/commands";
import {
  Decoration,
  DecorationSet,
  EditorView,
  WidgetType,
} from "@codemirror/view";
import type { SyntaxNode } from "@lezer/common";
import { postToSwift } from "../bridge";
import { renderInlineMarkdown } from "./inlineMarkdown";
import { cursorLineFromState, makeDecorationField, setWindowActiveEffect } from "./utils";

// ---------------------------------------------------------------------------
// Pure logic (DOM-less, unit-tested)
// ---------------------------------------------------------------------------

export interface CellRange {
  from: number;
  to: number;
  empty: boolean;
  /** Only meaningful when empty: whether a "|" closes this slot on the right. */
  closedByPipe: boolean;
  /** Number of "|" delimiters that must be synthesized before this slot (ragged row). */
  missingPipes: number;
}

export interface CellChange {
  from: number;
  to: number;
  insert: string;
}

function findTableNode(state: EditorState, tableFrom: number): SyntaxNode | null {
  let node: SyntaxNode | null = syntaxTree(state).resolveInner(tableFrom, 1);
  while (node && node.name !== "Table") node = node.parent;
  return node;
}

function tableRowNodes(table: SyntaxNode): SyntaxNode[] {
  const rows: SyntaxNode[] = [];
  for (let child = table.firstChild; child; child = child.nextSibling) {
    if (child.name === "TableHeader" || child.name === "TableRow") rows.push(child);
  }
  return rows;
}

// Maps a rendered cell (DOM row/cell index) to its document range via the
// syntax tree. DOM rowIndex 0 is the TableHeader; data rows follow as
// TableRow nodes (the delimiter line is not rendered). Empty cells have no
// TableCell node, so slots are tracked by counting pipes (TableDelimiter
// marks). The caller must bound cellIndex by the rendered column count.
export function resolveCellRange(
  state: EditorState,
  tableFrom: number,
  rowIndex: number,
  cellIndex: number,
): CellRange | null {
  const table = findTableNode(state, tableFrom);
  if (!table) return null;
  const row = tableRowNodes(table)[rowIndex];
  if (!row) return null;

  let slot = 0;
  let emptyFrom = row.from;
  for (let child = row.firstChild; child; child = child.nextSibling) {
    if (child.name === "TableDelimiter") {
      if (child.from > row.from) slot++;
      if (slot > cellIndex) {
        return { from: emptyFrom, to: child.from, empty: true, closedByPipe: true, missingPipes: 0 };
      }
      emptyFrom = child.to;
    } else if (child.name === "TableCell" && slot === cellIndex) {
      return { from: child.from, to: child.to, empty: false, closedByPipe: true, missingPipes: 0 };
    }
  }
  if (slot === cellIndex) {
    return { from: emptyFrom, to: row.to, empty: true, closedByPipe: false, missingPipes: 0 };
  }
  if (slot < cellIndex) {
    return { from: row.to, to: row.to, empty: true, closedByPipe: false, missingPipes: cellIndex - slot };
  }
  return null;
}

// Two-stage escape so any user input is representable inside a cell: every
// "|" in the output is preceded by an odd backslash run, which lezer's escape
// toggle always reads as an escaped pipe (a naive "|" -> "\|" pass turns user
// input "\|" into "\\|" — an escaped backslash followed by a RAW delimiter,
// corrupting the table).
export function escapeCell(text: string): string {
  let out = "";
  for (const ch of text) {
    if (ch === "\\") out += "\\\\";
    else if (ch === "|") out += "\\|";
    else out += ch;
  }
  return out;
}

export function unescapeCell(text: string): string {
  let out = "";
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const next = text[i + 1];
    if (ch === "\\" && (next === "\\" || next === "|")) {
      out += next;
      i++;
    } else {
      out += ch;
    }
  }
  return out;
}

export function countColumns(state: EditorState, tableFrom: number): number {
  const table = findTableNode(state, tableFrom);
  const header = table ? tableRowNodes(table)[0] : undefined;
  if (!header) return 0;
  let slot = 0;
  let last: SyntaxNode | null = null;
  for (let child = header.firstChild; child; child = child.nextSibling) {
    if (child.name === "TableDelimiter" && child.from > header.from) slot++;
    last = child;
  }
  return last && last.name === "TableDelimiter" ? slot : slot + 1;
}

export type CellNav = { row: number; col: number } | "append" | null;

export function nextCellLocation(
  rowCount: number,
  colCount: number,
  row: number,
  col: number,
  dir: "forward" | "backward" | "down",
): CellNav {
  if (dir === "forward") {
    if (col + 1 < colCount) return { row, col: col + 1 };
    if (row + 1 < rowCount) return { row: row + 1, col: 0 };
    return "append";
  }
  if (dir === "backward") {
    if (col > 0) return { row, col: col - 1 };
    if (row > 0) return { row: row - 1, col: colCount - 1 };
    return null;
  }
  return row + 1 < rowCount ? { row: row + 1, col } : null;
}

// Mixing piped and pipe-less row styles is valid GFM, so a fully piped empty
// row is always safe to append.
export function buildEmptyRowMarkdown(columns: number): string {
  return "|" + "   |".repeat(Math.max(1, columns));
}

// Splits a table row line into cell strings using the same escape toggle as
// lezer's parseRow (esc = !esc && ch === "\\"), so DOM cell indexes always
// match syntax-tree slots. Cell strings keep their escape sequences.
export function splitTableRow(line: string): string[] {
  const text = line.trim();
  const segments: string[] = [];
  let current = "";
  let esc = false;
  let endedWithPipe = false;
  for (const ch of text) {
    if (!esc && ch === "|") {
      segments.push(current);
      current = "";
      endedWithPipe = true;
    } else {
      esc = !esc && ch === "\\";
      current += ch;
      endedWithPipe = false;
    }
  }
  if (!endedWithPipe) segments.push(current);
  if (text.startsWith("|")) segments.shift();
  return segments.map((segment) => segment.trim());
}

// Tables whose lines carry a prefix (blockquote "> ", list indentation,
// leading spaces) render misaligned with the syntax tree, so in-place cell
// editing and row appends are disabled for them (raw editing still works).
export function tableHasLinePrefix(state: EditorState, tableFrom: number): boolean {
  const table = findTableNode(state, tableFrom);
  if (!table) return true;
  for (let child = table.firstChild; child; child = child.nextSibling) {
    if (child.from > state.doc.lineAt(child.from).from) return true;
  }
  return false;
}

// Re-anchors a table after its position shifted (e.g. content prepended by an
// external change): returns the table's position only when the markdown
// occurs exactly once in the document.
export function findTableByMarkdown(state: EditorState, markdown: string): number | null {
  if (markdown.length === 0) return null;
  const doc = state.doc.toString();
  const first = doc.indexOf(markdown);
  if (first === -1) return null;
  if (doc.indexOf(markdown, first + 1) !== -1) return null;
  return first;
}

function endsWithOddBackslashes(text: string): boolean {
  let count = 0;
  for (let i = text.length - 1; i >= 0 && text[i] === "\\"; i--) count++;
  return count % 2 === 1;
}

// Computes the doc changes for committing a cell edit (and optionally
// appending an empty row). Returns [] for a no-op, null when the table cannot
// be resolved or the cell content changed since the edit started (stale).
export function computeCellCommit(
  state: EditorState,
  tableFrom: number,
  rowIndex: number,
  cellIndex: number,
  newText: string,
  initialValue: string,
  originalRaw: string,
  appendRow: boolean,
): CellChange[] | null {
  // No-op detection compares input values, not doc slices: cells with escaped
  // whitespace (e.g. "| a\ |") would otherwise look changed and get rewritten.
  if (newText === initialValue && !appendRow) return [];
  const table = findTableNode(state, tableFrom);
  if (!table) return null;

  const changes: CellChange[] = [];
  if (newText !== initialValue) {
    const range = resolveCellRange(state, tableFrom, rowIndex, cellIndex);
    if (!range) return null;
    // Freshness check: abort instead of writing into a cell that changed
    // under the session (external edit).
    if (!range.empty && state.sliceDoc(range.from, range.to).trim() !== originalRaw) return null;
    if (range.empty && originalRaw !== "") return null;

    const escaped = escapeCell(newText.replace(/[\r\n]+/g, " ").trim());
    if (!range.empty) {
      let insert = escaped;
      // Defensive: a trailing odd backslash run directly before a pipe would
      // escape the delimiter (compact tables without padding).
      if (endsWithOddBackslashes(insert) && state.sliceDoc(range.to, range.to + 1) === "|") {
        insert += " ";
      }
      // Don't let clearing the only cell of a pipe-less row blank the line —
      // a blank line terminates the table block. Keep a lone pipe instead.
      if (insert.trim() === "") {
        const line = state.doc.lineAt(range.from);
        const remainder =
          line.text.slice(0, range.from - line.from) + line.text.slice(range.to - line.from);
        if (remainder.trim() === "") insert = "|";
      }
      changes.push({ from: range.from, to: range.to, insert });
    } else if (escaped.length > 0) {
      const insert = range.closedByPipe
        ? ` ${escaped} `
        : `${range.missingPipes > 0 ? " " : ""}${"|".repeat(range.missingPipes)} ${escaped}`;
      changes.push({ from: range.from, to: range.to, insert });
    }
  }
  if (appendRow) {
    if (tableHasLinePrefix(state, tableFrom)) return null;
    const endLine = state.doc.lineAt(table.to);
    changes.push({
      from: endLine.to,
      to: endLine.to,
      insert: "\n" + buildEmptyRowMarkdown(countColumns(state, tableFrom)),
    });
  }
  return changes;
}

// ---------------------------------------------------------------------------
// Cell edit session (DOM layer)
// ---------------------------------------------------------------------------

interface CellEditRequest {
  tableFrom: number;
  row: number;
  col: number;
  selectAll: boolean;
  wrap: HTMLElement;
  td: HTMLTableCellElement | null;
}

type FinishNext = CellEditRequest | "append" | null;

interface PendingFinish {
  next: FinishNext;
  commit: boolean;
  refocus: boolean;
}

interface CellEditSession {
  view: EditorView;
  tableFrom: number;
  tableMarkdown: string;
  row: number;
  col: number;
  input: HTMLInputElement;
  td: HTMLTableCellElement;
  wrap: HTMLElement;
  savedNodes: Node[];
  initialValue: string;
  originalRaw: string;
  composing: boolean;
  pendingFinish: PendingFinish | null;
  closed: boolean;
  controller: AbortController;
}

let activeCellEdit: CellEditSession | null = null;
// Hand-off slot for re-opening an editor after a commit dispatch rebuilt the
// widget DOM: set just before dispatch, filled by toDOM during the rebuild,
// consumed synchronously right after dispatch returns.
let pendingOpenWrap: { tableFrom: number; wrap: HTMLElement | null } | null = null;

let cellEditEndCallback: (() => void) | null = null;

export function isTableCellEditActive(): boolean {
  return activeCellEdit !== null;
}

// main.ts uses this to flush doc mutations (e.g. transcript chunks) deferred
// while a cell edit session was active.
export function setTableCellEditEndCallback(callback: () => void): void {
  cellEditEndCallback = callback;
}

function closeSession(session: CellEditSession): void {
  session.closed = true;
  session.controller.abort();
  if (activeCellEdit === session) activeCellEdit = null;
  cellEditEndCallback?.();
}

function restoreRendered(session: CellEditSession): void {
  const { td, savedNodes } = session;
  if (!td.isConnected) return;
  td.replaceChildren(...savedNodes);
  td.classList.remove("cm-table-cell-editing");
  td.style.removeProperty("width");
}

function tdAt(wrap: HTMLElement, row: number, col: number): HTMLTableCellElement | null {
  return wrap.querySelector("table")?.rows[row]?.cells[col] ?? null;
}

function fallbackToRaw(view: EditorView, tableFrom: number): void {
  view.dispatch({ selection: { anchor: tableFrom } });
  view.focus();
}

// While the window is inactive the widget can be shown even though the
// CodeMirror cursor sits inside the table's lines; move it out before editing
// so a later window re-activation rebuild cannot drop the widget mid-edit.
function evacuateSelection(view: EditorView, tableFrom: number): boolean {
  const state = view.state;
  const table = findTableNode(state, tableFrom);
  if (!table) return false;
  const startLine = state.doc.lineAt(table.from);
  const endLine = state.doc.lineAt(table.to);
  const headLine = state.doc.lineAt(state.selection.main.head).number;
  if (headLine < startLine.number || headLine > endLine.number) return true;
  let anchor: number;
  if (startLine.number > 1) {
    anchor = state.doc.line(startLine.number - 1).from;
  } else if (endLine.number < state.doc.lines) {
    anchor = state.doc.line(endLine.number + 1).from;
  } else {
    return false;
  }
  view.dispatch({ selection: { anchor } });
  return true;
}

// The single entry point for starting (or moving) a cell edit.
function requestCellEdit(
  view: EditorView,
  wrap: HTMLElement,
  tableFrom: number,
  td: HTMLTableCellElement,
  row: number,
  col: number,
  selectAll: boolean,
): void {
  const session = activeCellEdit;
  if (session && !session.closed) {
    if (session.td === td) return;
    finishCellEdit(session, { tableFrom, row, col, selectAll, wrap, td }, true, false);
    return;
  }
  if (view.state.readOnly) {
    // Selection changes are still allowed: keep the Phase 1 click-to-raw
    // behavior so the markdown stays viewable/copyable.
    fallbackToRaw(view, tableFrom);
    return;
  }
  if (tableHasLinePrefix(view.state, tableFrom)) {
    fallbackToRaw(view, tableFrom);
    return;
  }
  if (!evacuateSelection(view, tableFrom)) {
    fallbackToRaw(view, tableFrom);
    return;
  }
  const range = resolveCellRange(view.state, tableFrom, row, col);
  if (!range) {
    postToSwift({ type: "log", level: "debug", message: "table cell edit: range unresolved" });
    fallbackToRaw(view, tableFrom);
    return;
  }
  // Cells containing escape sequences outside the editor's round-trip domain
  // (e.g. "\*") would be silently rewritten on commit; edit them as raw
  // markdown instead.
  const raw = view.state.sliceDoc(range.from, range.to).trim();
  if (escapeCell(unescapeCell(raw)) !== raw) {
    fallbackToRaw(view, tableFrom);
    return;
  }
  openCellEditor(view, wrap, tableFrom, td, row, col, range, selectAll);
}

function openCellEditor(
  view: EditorView,
  wrap: HTMLElement,
  tableFrom: number,
  td: HTMLTableCellElement,
  row: number,
  col: number,
  range: CellRange,
  selectAll: boolean,
): void {
  const tableNode = findTableNode(view.state, tableFrom);
  const tableMarkdown = tableNode ? view.state.sliceDoc(tableNode.from, tableNode.to) : "";
  const raw = view.state.sliceDoc(range.from, range.to).trim();
  const initialValue = unescapeCell(raw);

  const input = document.createElement("input");
  input.type = "text";
  input.className = "cm-table-cell-input";
  input.spellcheck = false;
  input.setAttribute("autocapitalize", "off");
  input.setAttribute("autocorrect", "off");
  input.value = initialValue;

  const savedNodes = Array.from(td.childNodes);
  // Freeze the column width before swapping content so the auto table layout
  // does not reflow when rendered text is replaced by the input.
  td.style.width = `${td.getBoundingClientRect().width}px`;
  td.replaceChildren(input);
  td.classList.add("cm-table-cell-editing");

  const controller = new AbortController();
  const session: CellEditSession = {
    view,
    tableFrom,
    tableMarkdown,
    row,
    col,
    input,
    td,
    wrap,
    savedNodes,
    initialValue,
    originalRaw: raw,
    composing: false,
    pendingFinish: null,
    closed: false,
    controller,
  };
  activeCellEdit = session;

  const signal = controller.signal;
  input.addEventListener("keydown", (e) => handleCellKeydown(session, e), { signal });
  input.addEventListener("blur", () => {
    if (session.closed) return;
    if (session.composing) {
      // Queue the commit; it normally flushes on compositionend. WebKit fires
      // compositionend before blur on focus loss, so still being flagged as
      // composing one tick after blur means compositionend was dropped —
      // recover so the session (and the doc mutations deferred behind it)
      // cannot strand forever.
      finishCellEdit(session, null, true, false);
      window.setTimeout(() => {
        if (session.closed || !session.composing) return;
        if (document.activeElement === session.input) return;
        session.composing = false;
        flushPendingFinish(session);
      }, 0);
      return;
    }
    finishCellEdit(session, null, true, false);
  }, { signal });
  input.addEventListener("compositionstart", () => {
    session.composing = true;
  }, { signal });
  input.addEventListener("compositionend", () => {
    session.composing = false;
    flushPendingFinish(session);
  }, { signal });
  input.addEventListener("mousedown", (e) => e.stopPropagation(), { signal });
  input.addEventListener("click", (e) => e.stopPropagation(), { signal });
  // WKWebView does not blur the focused element when the panel loses key
  // status; commit on window-level deactivation signals so typed text never
  // lingers outside the document indefinitely.
  window.addEventListener("blur", () => {
    if (!session.closed) finishCellEdit(session, null, true, false);
  }, { signal });
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden" && !session.closed) {
      finishCellEdit(session, null, true, false);
    }
  }, { signal });

  input.focus();
  if (selectAll) input.select();
  else input.setSelectionRange(input.value.length, input.value.length);
}

function flushPendingFinish(session: CellEditSession): void {
  const pending = session.pendingFinish;
  if (!pending) return;
  session.pendingFinish = null;
  // Defer past WebKit's post-compositionend value settling.
  window.setTimeout(() => {
    if (!session.closed) finishCellEdit(session, pending.next, pending.commit, pending.refocus);
  }, 0);
}

function handleCellKeydown(session: CellEditSession, e: KeyboardEvent): void {
  e.stopPropagation();
  const composingKey = e.isComposing || e.keyCode === 229;
  if (session.composing && !composingKey) {
    // compositionend can be dropped on macOS (e.g. IME toggled via external
    // tools); a real key while flagged as composing means it is over.
    session.composing = false;
    flushPendingFinish(session);
  }
  if (composingKey) {
    // Swallow Tab so the browser's focus traversal cannot blur the input and
    // commit a half-composed value; Enter/Escape stay with the IME.
    if (e.key === "Tab") e.preventDefault();
    return;
  }
  const tableEl = session.wrap.querySelector("table");
  const rowCount = tableEl?.rows.length ?? 0;
  const colCount = tableEl?.rows[0]?.cells.length ?? 0;
  if (e.key === "Tab") {
    e.preventDefault();
    const dir = e.shiftKey ? "backward" : "forward";
    finishWithNav(session, nextCellLocation(rowCount, colCount, session.row, session.col, dir));
  } else if (e.key === "Enter") {
    e.preventDefault();
    finishWithNav(session, nextCellLocation(rowCount, colCount, session.row, session.col, "down"));
  } else if (e.key === "Escape") {
    e.preventDefault();
    finishCellEdit(session, null, false, true);
  }
  // Everything else (including Cmd+Z) stays native to the input.
}

function finishWithNav(session: CellEditSession, nav: CellNav): void {
  if (nav === null) {
    finishCellEdit(session, null, true, true);
  } else if (nav === "append") {
    finishCellEdit(session, "append", true, false);
  } else {
    finishCellEdit(session, {
      tableFrom: session.tableFrom,
      row: nav.row,
      col: nav.col,
      selectAll: true,
      wrap: session.wrap,
      td: tdAt(session.wrap, nav.row, nav.col),
    }, true, false);
  }
}

function finishCellEdit(
  session: CellEditSession,
  next: FinishNext,
  commit: boolean,
  refocus: boolean,
): void {
  if (session.closed) return;
  if (session.composing) {
    // Never commit mid-composition; run after compositionend (last wins).
    session.pendingFinish = { next, commit, refocus };
    return;
  }
  closeSession(session);
  const { view } = session;

  if (!commit) {
    restoreRendered(session);
    if (refocus) view.focus();
    return;
  }
  // DOM already torn down: destroy() owns the deferred-commit rescue path.
  if (!session.input.isConnected) return;

  const appendRow = next === "append";
  const changes = computeCellCommit(
    view.state,
    session.tableFrom,
    session.row,
    session.col,
    session.input.value,
    session.initialValue,
    session.originalRaw,
    appendRow,
  );
  if (changes === null) {
    postToSwift({ type: "log", level: "warn", message: "table cell commit aborted: table not resolvable or stale" });
    restoreRendered(session);
    if (refocus) view.focus();
    return;
  }

  let target: CellEditRequest | null = null;
  if (appendRow) {
    const tableEl = session.wrap.querySelector("table");
    target = {
      tableFrom: session.tableFrom,
      row: tableEl ? tableEl.rows.length : 1,
      col: 0,
      selectAll: true,
      wrap: session.wrap,
      td: null,
    };
  } else if (next) {
    target = next;
  }

  restoreRendered(session);

  if (changes.length > 0) {
    let mappedTableFrom = -1;
    if (target) {
      // Cross-table targets shift when the commit changes the doc length.
      mappedTableFrom = ChangeSet.of(changes, view.state.doc.length).mapPos(target.tableFrom, 1);
      pendingOpenWrap = { tableFrom: mappedTableFrom, wrap: null };
    }
    view.dispatch({
      changes,
      userEvent: "input.table",
      annotations: isolateHistory.of("full"),
    });
    if (target) {
      reopenAfterDispatch(view, target, mappedTableFrom);
    } else if (refocus) {
      view.focus();
    }
  } else {
    if (target) {
      const td = target.td?.isConnected ? target.td : tdAt(target.wrap, target.row, target.col);
      if (td) {
        requestCellEdit(view, target.wrap, target.tableFrom, td, target.row, target.col, target.selectAll);
        return;
      }
    }
    if (refocus) view.focus();
  }
}

// view.dispatch updates the DOM synchronously, so the next editor can be
// opened right after it returns — no requestAnimationFrame gap.
function reopenAfterDispatch(view: EditorView, target: CellEditRequest, mappedTableFrom: number): void {
  // Widget DOM survived (eq() true, e.g. a table before the committed one).
  if (target.td?.isConnected) {
    pendingOpenWrap = null;
    requestCellEdit(view, target.wrap, mappedTableFrom, target.td, target.row, target.col, target.selectAll);
    return;
  }
  // Widget was rebuilt: toDOM recorded the new wrap during the dispatch.
  const wrap = pendingOpenWrap?.wrap ?? null;
  pendingOpenWrap = null;
  if (!wrap || !wrap.isConnected) return; // widget not visible (e.g. outside viewport)
  const td = tdAt(wrap, target.row, target.col);
  if (td) requestCellEdit(view, wrap, mappedTableFrom, td, target.row, target.col, target.selectAll);
}

// Commits the active session when the note window is deactivated (Swift sends
// setWindowActiveEffect). Deferred because committing dispatches a transaction.
const cellEditDeactivateListener = EditorView.updateListener.of((update) => {
  if (!activeCellEdit) return;
  const deactivated = update.transactions.some((tr) =>
    tr.effects.some((e) => e.is(setWindowActiveEffect) && e.value === false),
  );
  if (!deactivated) return;
  const session = activeCellEdit;
  window.setTimeout(() => {
    if (session && !session.closed) finishCellEdit(session, null, true, false);
  }, 0);
});

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class TableWidget extends WidgetType {
  constructor(private markdown: string, private tableFrom: number) {
    super();
  }

  eq(other: TableWidget): boolean {
    return other.markdown === this.markdown && other.tableFrom === this.tableFrom;
  }

  toDOM(view: EditorView): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "cm-table-widget";
    wrap.dataset.tableFrom = String(this.tableFrom);

    // Two layers: the outer wrap anchors the hover button; the inner scroller
    // owns overflow-x so the button stays pinned while the table scrolls.
    const scroll = document.createElement("div");
    scroll.className = "cm-table-scroll";
    scroll.appendChild(buildTable(this.markdown));
    wrap.appendChild(scroll);

    const sourceBtn = document.createElement("button");
    sourceBtn.className = "cm-source-edit-btn";
    sourceBtn.textContent = "</>";
    sourceBtn.title = "Edit as Markdown";
    sourceBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      const session = activeCellEdit;
      if (session && session.wrap === wrap) {
        // Don't switch modes under the IME; the user keeps editing.
        if (session.composing) return;
        finishCellEdit(session, null, true, false);
      }
      view.dispatch({ selection: { anchor: this.tableFrom } });
      view.focus();
    });
    wrap.appendChild(sourceBtn);

    // Keep mousedown away from focus handling except inside the cell input
    // (caret placement there must stay native).
    wrap.addEventListener("mousedown", (e) => {
      if ((e.target as HTMLElement).closest(".cm-table-cell-input")) return;
      e.preventDefault();
    });

    wrap.addEventListener("click", (e) => {
      const target = e.target as HTMLElement;
      if (target.closest(".cm-table-cell-input")) return;
      const cell = target.closest("td, th");
      if (!(cell instanceof HTMLTableCellElement)) return;
      e.preventDefault();
      const rowEl = cell.parentElement as HTMLTableRowElement;
      requestCellEdit(view, wrap, this.tableFrom, cell, rowEl.rowIndex, cell.cellIndex, false);
    });

    if (pendingOpenWrap && pendingOpenWrap.tableFrom === this.tableFrom) {
      pendingOpenWrap.wrap = wrap;
    }
    return wrap;
  }

  // Fired on scroll-out (viewport virtualization — a routine gesture) and on
  // external doc changes. Rescue the typed text with a deferred commit; the
  // freshness check aborts it exactly in the true external-change case.
  destroy(dom: HTMLElement): void {
    const session = activeCellEdit;
    if (!session || session.wrap !== dom) return;
    const { view, tableFrom, tableMarkdown, row, col, input, initialValue, originalRaw, composing } = session;
    const value = input.value;
    if (composing) {
      closeSession(session);
      if (value !== initialValue) {
        postToSwift({ type: "log", level: "warn", message: "table cell edit discarded: widget destroyed during IME composition" });
      }
      // Re-anchor the orphaned IME session so pending marked text cannot leak
      // into the next focused element.
      window.requestAnimationFrame(() => view.focus());
      return;
    }
    // Scheduled before closeSession: its end callback schedules the deferred
    // transcript flush, and same-delay timers run FIFO — the rescue must
    // resolve the table before that flush shifts the doc.
    window.setTimeout(() => {
      const state = view.state;
      // A stale tableFrom can resolve into a different table whose cell
      // happens to pass the content freshness check; require the table
      // markdown to match before trusting the position.
      let from: number | null = null;
      const node = findTableNode(state, tableFrom);
      if (node && state.sliceDoc(node.from, node.to) === tableMarkdown) {
        from = node.from;
      } else {
        from = findTableByMarkdown(state, tableMarkdown);
      }
      const changes = from === null
        ? null
        : computeCellCommit(state, from, row, col, value, initialValue, originalRaw, false);
      if (changes === null) {
        if (value !== initialValue) {
          postToSwift({ type: "log", level: "warn", message: "table cell edit discarded: table changed externally" });
        }
        return;
      }
      if (changes.length > 0) {
        postToSwift({ type: "log", level: "debug", message: "table cell edit committed after widget teardown" });
        view.dispatch({
          changes,
          userEvent: "input.table",
          annotations: isolateHistory.of("full"),
        });
      }
    }, 0);
    closeSession(session);
  }

  ignoreEvent(): boolean {
    return true;
  }
}

function buildTable(md: string): HTMLTableElement {
  const lines = md.trim().split("\n");
  const table = document.createElement("table");
  if (lines.length < 2) return table;

  const headers = splitTableRow(lines[0]);
  const dataRows = lines.slice(2).map(splitTableRow);

  const thead = table.createTHead();
  const headerRow = thead.insertRow();
  for (const h of headers) {
    const th = document.createElement("th");
    th.appendChild(renderInlineMarkdown(h));
    headerRow.appendChild(th);
  }

  const tbody = table.createTBody();
  for (const row of dataRows) {
    const tr = tbody.insertRow();
    // Pad/truncate to the header column count (GFM rendering semantics), so
    // every navigable slot has a real cell.
    for (let i = 0; i < headers.length; i++) {
      const td = tr.insertCell();
      td.appendChild(renderInlineMarkdown(row[i] ?? ""));
    }
  }

  return table;
}

function buildTableDecorations(state: EditorState): DecorationSet {
  const cursorLine = cursorLineFromState(state);
  const decorations: Range<Decoration>[] = [];

  syntaxTree(state).iterate({
    enter: (node) => {
      if (node.name !== "Table") return;
      const startLine = state.doc.lineAt(node.from);
      const endLine = state.doc.lineAt(node.to);
      if (cursorLine >= startLine.number && cursorLine <= endLine.number) return;

      const tableMarkdown = state.sliceDoc(node.from, node.to);
      decorations.push(
        Decoration.replace({
          widget: new TableWidget(tableMarkdown, node.from),
        }).range(startLine.from, endLine.to),
      );
    },
  });

  return decorations.length > 0 ? Decoration.set(decorations) : Decoration.none;
}

export const tableExtension = [
  makeDecorationField(buildTableDecorations),
  cellEditDeactivateListener,
];
