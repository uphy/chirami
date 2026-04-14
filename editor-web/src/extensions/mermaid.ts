import { syntaxTree } from "@codemirror/language";
import { EditorState, Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  WidgetType,
} from "@codemirror/view";
import mermaid from "mermaid";
import { CodeBlockSizeOptions, applySizeOptions, cursorLineFromState, makeDecorationField, parseCodeBlockInfo, sizeOptionsEq } from "./utils";

mermaid.initialize({ startOnLoad: false, theme: "neutral" });

class MermaidWidget extends WidgetType {
  constructor(
    private code: string,
    private readonly sizeOptions: CodeBlockSizeOptions = {},
  ) {
    super();
  }

  eq(other: MermaidWidget): boolean {
    return other.code === this.code && sizeOptionsEq(other.sizeOptions, this.sizeOptions);
  }

  toDOM(view: EditorView): HTMLElement {
    const container = document.createElement("div");
    container.className = "cm-mermaid-container";
    applySizeOptions(container, this.sizeOptions);

    // mermaid.render() requires a unique id for internal element creation
    const id = `mermaid-widget-${crypto.randomUUID()}`;
    mermaid
      .render(id, this.code)
      .then(({ svg }) => {
        if (container.isConnected) {
          container.innerHTML = svg;
          view.requestMeasure();
        }
      })
      .catch((err: Error) => {
        if (container.isConnected) {
          container.textContent = err.message;
          container.className = "cm-mermaid-error";
          view.requestMeasure();
        }
      });

    return container;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

function buildMermaidDecorations(state: EditorState): DecorationSet {
  const cursorLine = cursorLineFromState(state);
  const decorations: Range<Decoration>[] = [];

  syntaxTree(state).iterate({
    enter: (node) => {
      if (node.name !== "FencedCode") return;

      const codeInfoNode = node.node.getChild("CodeInfo");
      if (!codeInfoNode) return false;
      const { lang, options: sizeOptions } = parseCodeBlockInfo(
        state.sliceDoc(codeInfoNode.from, codeInfoNode.to)
      );
      if (lang !== "mermaid") return false;

      const startLine = state.doc.lineAt(node.from);
      const endLine = state.doc.lineAt(node.to);
      if (cursorLine >= startLine.number && cursorLine <= endLine.number) return false;

      const codeTextNode = node.node.getChild("CodeText");
      const code = codeTextNode
        ? state.sliceDoc(codeTextNode.from, codeTextNode.to).trim()
        : "";

      decorations.push(
        Decoration.replace({
          widget: new MermaidWidget(code, sizeOptions),
        }).range(startLine.from, endLine.to),
      );

      return false;
    },
  });

  return decorations.length > 0 ? Decoration.set(decorations) : Decoration.none;
}

export const mermaidExtension = makeDecorationField(buildMermaidDecorations);
