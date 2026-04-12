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
import { cursorLineNumber, nodeContainsCursorLine, shouldRebuild } from "./utils";

// Markdown syntax marks to hide on non-cursor lines.
// ListMark ("-", "*", "+") is handled separately below with bullet replacement.
const HIDDEN_MARK_NODES = new Set([
  "HeaderMark",
  "EmphasisMark",
  "CodeMark",
  "CodeInfo",
  "LinkMark",
  "URL",
  "StrikethroughMark",
  "QuoteMark",
]);

const HIDDEN_DECORATION = Decoration.replace({ inclusive: false });
const CODE_BLOCK_LINE       = Decoration.line({ class: "cm-code-block-line" });
const CODE_BLOCK_LINE_FIRST = Decoration.line({ class: "cm-code-block-line cm-code-block-first" });
const CODE_BLOCK_LINE_LAST  = Decoration.line({ class: "cm-code-block-line cm-code-block-last" });
const CODE_BLOCK_LINE_ONLY  = Decoration.line({ class: "cm-code-block-line cm-code-block-first cm-code-block-last" });
const QUOTE_LINE            = Decoration.line({ class: "cm-quote" });

class BulletWidget extends WidgetType {
  eq(): boolean {
    return true;
  }

  toDOM(): HTMLElement {
    const span = document.createElement("span");
    span.textContent = "•";
    span.className = "cm-list-bullet";
    return span;
  }
}

// Stateless singleton — BulletWidget.eq() always returns true so one instance is sufficient.
const BULLET_DECORATION = Decoration.replace({ widget: new BulletWidget() });

class LivePreviewPlugin {
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
    const tree = syntaxTree(view.state);
    const processedCodeLines = new Set<number>();

    for (const { from, to } of view.visibleRanges) {
      tree.iterate({
        from,
        to,
        enter: (node) => {
          if (node.name === "Blockquote") {
            const startLine = view.state.doc.lineAt(Math.max(node.from, from)).number;
            const endLine   = view.state.doc.lineAt(Math.min(node.to, to)).number;
            for (let lineNum = startLine; lineNum <= endLine; lineNum++) {
              const line = view.state.doc.line(lineNum);
              decorations.push(QUOTE_LINE.range(line.from));
            }
            return; // Continue into children for QuoteMark handling
          }

          if (node.name === "FencedCode") {
            // mermaidExtension owns the rendered widget; skip duplicate line decorations
            const cursorInBlock = nodeContainsCursorLine(view, node.from, node.to, cursorLine);
            if (!cursorInBlock) {
              const codeInfoNode = node.node.getChild("CodeInfo");
              if (codeInfoNode) {
                const lang = view.state
                  .sliceDoc(codeInfoNode.from, codeInfoNode.to)
                  .trim()
                  .toLowerCase();
                if (lang === "mermaid") return false;
              }
            }

            const fullStart = view.state.doc.lineAt(node.from).number;
            const fullEnd   = view.state.doc.lineAt(node.to).number;
            const visStart  = view.state.doc.lineAt(Math.max(node.from, from)).number;
            const visEnd    = view.state.doc.lineAt(Math.min(node.to, to)).number;
            for (let lineNum = visStart; lineNum <= visEnd; lineNum++) {
              const line = view.state.doc.line(lineNum);
              if (!processedCodeLines.has(line.from)) {
                processedCodeLines.add(line.from);
                const isFirst = lineNum === fullStart;
                const isLast  = lineNum === fullEnd;
                const deco =
                  isFirst && isLast ? CODE_BLOCK_LINE_ONLY :
                  isFirst           ? CODE_BLOCK_LINE_FIRST :
                  isLast            ? CODE_BLOCK_LINE_LAST  :
                                      CODE_BLOCK_LINE;
                decorations.push(deco.range(line.from));
              }
            }
            return; // Continue into children so CodeMark is still processed
          }

          if (node.name === "ListMark") {
            if (nodeContainsCursorLine(view, node.from, node.to, cursorLine)) return;
            const markText = view.state.sliceDoc(node.from, node.to);
            // Detect task list item: text after the mark starts with " [ ]" or " [x]"
            const afterMark = view.state.sliceDoc(node.to, node.to + 4);
            const isTaskItem = /^ \[[ xX]\]/.test(afterMark);
            const isOrderedMark = /^\d+[.)]$/.test(markText);
            if (isTaskItem) {
              // Task list: hide the dash (checkbox widget follows from checkboxExtension)
              decorations.push(HIDDEN_DECORATION.range(node.from, node.to));
            } else if (!isOrderedMark) {
              // Unordered list: replace dash/asterisk/plus with bullet symbol
              decorations.push(BULLET_DECORATION.range(node.from, node.to));
            }
            // Ordered list marks (e.g. "1.") are left as-is
            return;
          }

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
