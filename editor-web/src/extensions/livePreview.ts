import { syntaxTree } from "@codemirror/language";
import { Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
} from "@codemirror/view";

// Markdown syntax marks to hide on non-cursor lines
const HIDDEN_MARK_NODES = new Set([
  "HeaderMark",
  "EmphasisMark",
  "CodeMark",
  "LinkMark",
  "URL",
  "StrikethroughMark",
  "ListMark",
  "QuoteMark",
]);

const HIDDEN_DECORATION = Decoration.replace({ inclusive: false });

function nodeContainsCursorLine(
  view: EditorView,
  from: number,
  to: number,
  cursorLine: number
): boolean {
  const startLine = view.state.doc.lineAt(from).number;
  const endLine = view.state.doc.lineAt(to).number;
  return cursorLine >= startLine && cursorLine <= endLine;
}

class LivePreviewPlugin {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged) {
      this.decorations = this.build(update.view);
    } else if (update.selectionSet) {
      const newLine = update.view.state.doc.lineAt(
        update.view.state.selection.main.head
      ).number;
      const oldLine = update.startState.doc.lineAt(
        update.startState.selection.main.head
      ).number;
      if (newLine !== oldLine) {
        this.decorations = this.build(update.view);
      }
    }
  }

  private build(view: EditorView): DecorationSet {
    const cursorLine = view.state.doc.lineAt(
      view.state.selection.main.head
    ).number;
    const decorations: Range<Decoration>[] = [];
    const tree = syntaxTree(view.state);

    for (const { from, to } of view.visibleRanges) {
      tree.iterate({
        from,
        to,
        enter: (node) => {
          if (!HIDDEN_MARK_NODES.has(node.name)) return;
          if (nodeContainsCursorLine(view, node.from, node.to, cursorLine)) {
            return;
          }
          decorations.push(HIDDEN_DECORATION.range(node.from, node.to));
        },
      });
    }

    return Decoration.set(decorations, true);
  }
}

export const livePreview = ViewPlugin.fromClass(LivePreviewPlugin, {
  decorations: (v) => v.decorations,
});
