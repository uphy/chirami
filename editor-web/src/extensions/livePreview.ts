import { syntaxTree } from "@codemirror/language";
import { Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
} from "@codemirror/view";
import { cursorLineNumber, nodeContainsCursorLine, shouldRebuild } from "./utils";

// Markdown syntax marks to hide on non-cursor lines.
// ListMark ("-", "*", "+") is handled separately below with bullet replacement.
// HeaderMark ("# ") is handled separately below to also hide the trailing space.
const HIDDEN_MARK_NODES = new Set([
  "EmphasisMark",
  "CodeMark",
  "CodeInfo",
  "LinkMark",
  "URL",
  "StrikethroughMark",
  "QuoteMark",
]);

const HIDDEN_DECORATION = Decoration.replace({ inclusive: false });
// Used to hide the list mark ("- ") on top-level unordered items. Unlike
// HIDDEN_DECORATION (Decoration.replace), a mark decoration keeps the span in
// the DOM but CSS display:none removes it from the inline formatting context
// entirely — no element boundary remains to act as a soft-wrap opportunity
// under overflow-wrap:anywhere (WebKit would otherwise break there first).
const LIST_MARK_HIDDEN  = Decoration.mark({ class: "cm-list-mark-hidden" });
// Applied to the "- " mark on top-level cursor lines: positions it absolutely
// in the same left gutter as the rendered ::before bullet on non-cursor lines.
const LIST_MARK_CURSOR      = Decoration.mark({ class: "cm-list-mark-cursor" });
// Applied to the "- " mark on nested cursor lines: same absolute positioning
// but left offset is driven by --hang-n (inherited from the cm-line element).
const LIST_MARK_CURSOR_HANG = Decoration.mark({ class: "cm-list-mark-cursor-hang" });
const CODE_BLOCK_LINE       = Decoration.line({ class: "cm-code-block-line" });
const CODE_BLOCK_LINE_FIRST = Decoration.line({ class: "cm-code-block-line cm-code-block-first" });
const CODE_BLOCK_LINE_LAST  = Decoration.line({ class: "cm-code-block-line cm-code-block-last" });
const CODE_BLOCK_LINE_ONLY  = Decoration.line({ class: "cm-code-block-line cm-code-block-first cm-code-block-last" });
const QUOTE_LINE            = Decoration.line({ class: "cm-quote" });


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
                if (lang === "mermaid" || lang === "tldraw") return false;
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

          if (node.name === "HeaderMark") {
            if (nodeContainsCursorLine(view, node.from, node.to, cursorLine)) return;
            // Also hide the trailing space after "#" so the heading text aligns
            // with the paragraph left edge. The Lezer Markdown parser stores
            // HeaderMark as only the "#" characters (without the space), so the
            // space would otherwise remain visible with the enlarged heading
            // font-size, causing the text to appear shifted right.
            const charAfter = view.state.sliceDoc(node.to, node.to + 1);
            const end = (charAfter === " " || charAfter === "\t") ? node.to + 1 : node.to;
            decorations.push(HIDDEN_DECORATION.range(node.from, end));
            return;
          }

          if (node.name === "ListItem") {
            const itemLine = view.state.doc.lineAt(node.from);
            const match = /^([ \t]*)([-*+])/.exec(itemLine.text);
            if (!match) return;
            // Exclude task items — their checkbox serves as the visual marker
            const isTaskItem = /^ \[[ xX]\]/.test(itemLine.text.slice(match[0].length));
            if (isTaskItem) return;

            if (match[1].length === 0) {
              // Top-level: use cm-list-hanging (position:relative + padding-left:1.5em)
              // with an absolutely-positioned mark in the left gutter.
              // Cursor lines get cm-list-hanging-cursor to suppress the ::before bullet.
              const cls = itemLine.number === cursorLine
                ? "cm-list-hanging cm-list-hanging-cursor"
                : "cm-list-hanging";
              decorations.push(
                Decoration.line({ class: cls }).range(itemLine.from)
              );
            } else {
              // Nested: hide leading whitespace and apply hanging indent on both
              // cursor and non-cursor lines (same principle as top-level).
              // Cursor lines get cm-list-hang-cursor to suppress the ::before bullet;
              // LIST_MARK_CURSOR_HANG then renders "- " absolutely in the gutter.
              decorations.push(HIDDEN_DECORATION.range(itemLine.from, itemLine.from + match[1].length));
              let spaces = 0;
              for (const ch of match[1]) spaces += ch === "\t" ? 4 : 1;
              const cls = itemLine.number === cursorLine
                ? "cm-list-hang cm-list-hang-cursor"
                : "cm-list-hang";
              decorations.push(
                Decoration.line({ class: cls, attributes: { style: `--hang-n: ${spaces}` } }).range(itemLine.from)
              );
            }
            return; // Continue into children for ListMark and other handling
          }

          if (node.name === "ListMark") {
            const markText = view.state.sliceDoc(node.from, node.to);
            // Detect task list item: text after the mark starts with " [ ]" or " [x]"
            const afterMark = view.state.sliceDoc(node.to, node.to + 4);
            const isTaskItem = /^ \[[ xX]\]/.test(afterMark);
            const isOrderedMark = /^\d+[.)]$/.test(markText);
            if (!isOrderedMark) {
              const charAfter = view.state.sliceDoc(node.to, node.to + 1);
              const end = (charAfter === " " || charAfter === "\t") ? node.to + 1 : node.to;
              const markLine = view.state.doc.lineAt(node.from);
              if (nodeContainsCursorLine(view, node.from, node.to, cursorLine)) {
                if (!isTaskItem) {
                  if (node.from === markLine.from) {
                    // Top-level cursor: position in the far-left gutter.
                    decorations.push(LIST_MARK_CURSOR.range(node.from, end));
                  } else {
                    // Nested cursor: position in the level-appropriate gutter.
                    // left is driven by --hang-n inherited from the cm-line element.
                    decorations.push(LIST_MARK_CURSOR_HANG.range(node.from, end));
                  }
                }
                return;
              }
              if (isTaskItem || node.from === markLine.from) {
                // Top-level or task item: hide "- " via display:none mark.
                // display:none removes the span from the inline formatting context,
                // so no element boundary exists to be a soft-wrap opportunity.
                decorations.push(LIST_MARK_HIDDEN.range(node.from, end));
              } else {
                // Nested non-task: hide "- " via display:none (same as top-level)
                decorations.push(LIST_MARK_HIDDEN.range(node.from, end));
              }
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
