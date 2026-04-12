import { syntaxTree } from "@codemirror/language";
import { Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
  WidgetType,
} from "@codemirror/view";
import { cursorLineNumber, shouldRebuild } from "./utils";

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
    th.textContent = h;
    headerRow.appendChild(th);
  }

  const tbody = table.createTBody();
  for (const row of dataRows) {
    const tr = tbody.insertRow();
    for (const cell of row) {
      const td = tr.insertCell();
      td.textContent = cell;
    }
  }

  return table;
}

const tableHideMark = Decoration.mark({ class: "cm-table-raw" });

class TablePlugin {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate) {
    if (shouldRebuild(update)) {
      this.decorations = this.build(update.view);
    }
  }

  private build(view: EditorView): DecorationSet {
    const cursorLine = cursorLineNumber(view);
    const decorations: Range<Decoration>[] = [];

    for (const { from, to } of view.visibleRanges) {
      syntaxTree(view.state).iterate({
        from,
        to,
        enter: (node) => {
          if (node.name !== "Table") return;
          const startLine = view.state.doc.lineAt(node.from);
          const endLine = view.state.doc.lineAt(node.to);
          if (cursorLine >= startLine.number && cursorLine <= endLine.number) return;

          const tableMarkdown = view.state.sliceDoc(node.from, node.to);

          // block: false — inline widget inserted at start of table
          decorations.push(
            Decoration.widget({
              widget: new TableWidget(tableMarkdown),
              side: -1,
            }).range(startLine.from),
          );
          decorations.push(tableHideMark.range(startLine.from, endLine.to));
        },
      });
    }

    return decorations.length > 0 ? Decoration.set(decorations, true) : Decoration.none;
  }
}

export const tableExtension = ViewPlugin.fromClass(TablePlugin, {
  decorations: (v) => v.decorations,
});
