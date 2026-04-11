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

class CheckboxWidget extends WidgetType {
  constructor(
    private checked: boolean,
    private innerPos: number,
  ) {
    super();
  }

  eq(other: CheckboxWidget): boolean {
    return other.checked === this.checked && other.innerPos === this.innerPos;
  }

  toDOM(view: EditorView): HTMLElement {
    const wrap = document.createElement("span");
    wrap.className = "cm-checkbox-widget";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = this.checked;
    input.addEventListener("mousedown", (e) => e.preventDefault());
    input.addEventListener("click", (e) => {
      e.stopPropagation();
      const nextChar = this.checked ? " " : "x";
      view.dispatch({
        changes: { from: this.innerPos, to: this.innerPos + 1, insert: nextChar },
      });
    });
    wrap.appendChild(input);
    return wrap;
  }

  ignoreEvent(): boolean {
    return false;
  }
}

class CheckboxPlugin {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate) {
    if (shouldRebuild(update)) this.decorations = this.build(update.view);
  }

  private build(view: EditorView): DecorationSet {
    const cursorLine = cursorLineNumber(view);
    const decorations: Range<Decoration>[] = [];
    for (const { from, to } of view.visibleRanges) {
      syntaxTree(view.state).iterate({
        from,
        to,
        enter: (node) => {
          // TaskMarker is the "[ ]" or "[x]" portion of a GFM task list item
          if (node.name !== "TaskMarker") return;
          const nodeLine = view.state.doc.lineAt(node.from).number;
          if (nodeLine === cursorLine) return;
          const markerText = view.state.sliceDoc(node.from, node.to);
          if (!/^\[[ xX]\]$/.test(markerText)) return;
          const checked = /^\[[xX]\]$/.test(markerText);
          const innerPos = node.from + 1; // position of ' ' or 'x' inside brackets
          if (checked) {
            const line = view.state.doc.lineAt(node.from);
            decorations.push(
              Decoration.line({ class: "cm-task-checked" }).range(line.from),
            );
          }
          decorations.push(
            Decoration.replace({
              widget: new CheckboxWidget(checked, innerPos),
            }).range(node.from, node.to),
          );
        },
      });
    }
    return Decoration.set(decorations, true);
  }
}

export const checkboxExtension = ViewPlugin.fromClass(CheckboxPlugin, {
  decorations: (v) => v.decorations,
});
