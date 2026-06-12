import { syntaxTree } from "@codemirror/language";
import { EditorState, Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  WidgetType,
} from "@codemirror/view";
import type { SyntaxNode } from "@lezer/common";
import { renderInlineMarkdown } from "./inlineMarkdown";
import { cursorLineFromState, makeDecorationField } from "./utils";

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
    wrap.appendChild(buildTable(this.markdown));

    wrap.addEventListener("mousedown", (e) => e.preventDefault());

    // Cell click: enter raw-edit mode with the cursor at the end of the
    // clicked cell's content. The decoration build skips the table once the
    // cursor is inside its line range, revealing the raw Markdown.
    wrap.addEventListener("click", (e) => {
      const cell = (e.target as HTMLElement).closest("td, th");
      if (!(cell instanceof HTMLTableCellElement)) return;
      e.preventDefault();
      const row = cell.parentElement as HTMLTableRowElement;
      const pos = cellDocPos(view.state, this.tableFrom, row.rowIndex, cell.cellIndex);
      view.dispatch({ selection: { anchor: pos } });
      view.focus();
    });

    return wrap;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

// Maps a rendered cell (DOM row/cell index) to its document position via the
// syntax tree. DOM rowIndex 0 is the TableHeader; data rows follow as
// TableRow nodes (the delimiter line is not rendered).
export function cellDocPos(
  state: EditorState,
  tableFrom: number,
  rowIndex: number,
  cellIndex: number,
): number {
  let table: SyntaxNode | null = syntaxTree(state).resolveInner(tableFrom, 1);
  while (table && table.name !== "Table") table = table.parent;
  if (!table) return tableFrom;

  const rows: SyntaxNode[] = [];
  for (let child = table.firstChild; child; child = child.nextSibling) {
    if (child.name === "TableHeader" || child.name === "TableRow") rows.push(child);
  }
  const row = rows[rowIndex];
  if (!row) return tableFrom;

  // Empty cells have no TableCell node, so cells can't be indexed directly.
  // Walk the row tracking the slot between pipes (TableDelimiter marks).
  let slot = 0;
  let emptyPos = row.from;
  for (let child = row.firstChild; child; child = child.nextSibling) {
    if (child.name === "TableDelimiter") {
      if (child.from > row.from) slot++;
      if (slot > cellIndex) return emptyPos;
      emptyPos = child.to;
    } else if (child.name === "TableCell" && slot === cellIndex) {
      return child.to;
    }
  }
  return row.to;
}

function buildTable(md: string): HTMLTableElement {
  const lines = md.trim().split("\n");
  const table = document.createElement("table");
  if (lines.length < 2) return table;

  const parseRow = (line: string): string[] =>
    line.replace(/^\||\|$/g, "").split("|").map((c) => c.trim());

  const headers = parseRow(lines[0]);
  const dataRows = lines.slice(2).map(parseRow);

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
    for (const cell of row) {
      const td = tr.insertCell();
      td.appendChild(renderInlineMarkdown(cell));
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

export const tableExtension = makeDecorationField(buildTableDecorations);
