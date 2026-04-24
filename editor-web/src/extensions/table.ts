import { syntaxTree } from "@codemirror/language";
import { EditorState, Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  WidgetType,
} from "@codemirror/view";
import { renderInlineMarkdown } from "./inlineMarkdown";
import { cursorLineFromState, makeDecorationField } from "./utils";

class TableWidget extends WidgetType {
  constructor(private markdown: string) {
    super();
  }

  eq(other: TableWidget): boolean {
    return other.markdown === this.markdown;
  }

  toDOM(): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "cm-table-widget";
    wrap.appendChild(buildTable(this.markdown));
    return wrap;
  }

  ignoreEvent(): boolean {
    return true;
  }
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
          widget: new TableWidget(tableMarkdown),
        }).range(startLine.from, endLine.to),
      );
    },
  });

  return decorations.length > 0 ? Decoration.set(decorations) : Decoration.none;
}

export const tableExtension = makeDecorationField(buildTableDecorations);
