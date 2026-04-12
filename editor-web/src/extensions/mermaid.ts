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
import mermaid from "mermaid";
import { cursorLineNumber, nodeContainsCursorLine, shouldRebuild } from "./utils";

mermaid.initialize({ startOnLoad: false, theme: "neutral" });

const mermaidHideMark = Decoration.mark({ class: "cm-mermaid-raw" });

class MermaidWidget extends WidgetType {
  constructor(private code: string) {
    super();
  }

  eq(other: MermaidWidget): boolean {
    return other.code === this.code;
  }

  toDOM(): HTMLElement {
    const container = document.createElement("div");
    container.className = "cm-mermaid-container";

    // mermaid.render() requires a unique id for internal element creation
    const id = `mermaid-widget-${crypto.randomUUID()}`;
    mermaid
      .render(id, this.code)
      .then(({ svg }) => {
        if (container.isConnected) container.innerHTML = svg;
      })
      .catch((err: Error) => {
        if (container.isConnected) {
          container.textContent = err.message;
          container.className = "cm-mermaid-error";
        }
      });

    return container;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

class MermaidPlugin {
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
          if (node.name !== "FencedCode") return;

          const codeInfoNode = node.node.getChild("CodeInfo");
          if (!codeInfoNode) return false;
          const lang = view.state
            .sliceDoc(codeInfoNode.from, codeInfoNode.to)
            .trim()
            .toLowerCase();
          if (lang !== "mermaid") return false;

          if (nodeContainsCursorLine(view, node.from, node.to, cursorLine)) return false;

          const startLine = view.state.doc.lineAt(node.from);
          const endLine = view.state.doc.lineAt(node.to);

          const codeTextNode = node.node.getChild("CodeText");
          const code = codeTextNode
            ? view.state.sliceDoc(codeTextNode.from, codeTextNode.to).trim()
            : "";

          decorations.push(
            Decoration.widget({
              widget: new MermaidWidget(code),
              side: -1,
            }).range(startLine.from),
          );
          decorations.push(mermaidHideMark.range(startLine.from, endLine.to));

          return false;
        },
      });
    }

    return decorations.length > 0
      ? Decoration.set(decorations, true)
      : Decoration.none;
  }
}

export const mermaidExtension = ViewPlugin.fromClass(MermaidPlugin, {
  decorations: (v) => v.decorations,
});
