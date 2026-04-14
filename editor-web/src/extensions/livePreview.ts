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

// Replaces the full task-item prefix ("  - [ ] " or "  - [x] ") with a native
// checkbox input. innerPos points to the character inside the brackets so the
// click handler can toggle it in-document.
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
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = this.checked;
    input.tabIndex = -1;
    input.addEventListener("mousedown", (e) => e.preventDefault());
    input.addEventListener("click", (e) => {
      e.stopPropagation();
      const nextChar = this.checked ? " " : "x";
      view.dispatch({
        changes: { from: this.innerPos, to: this.innerPos + 1, insert: nextChar },
      });
    });
    return input;
  }

  ignoreEvent(): boolean {
    return false;
  }
}

// Replaces the leading prefix (whitespace + "- " + trailing space) of a list
// item with an inline-block bullet widget. The widget width equals the total
// indent so text flows naturally after it, and cursor positions are natural.
class BulletWidget extends WidgetType {
  constructor(private widthEm: number) { super(); }

  eq(other: BulletWidget): boolean {
    return other.widthEm === this.widthEm;
  }

  toDOM(): HTMLElement {
    const span = document.createElement("span");
    span.className = "cm-bullet-widget";
    span.style.width = `${this.widthEm}em`;
    span.textContent = "•";
    return span;
  }

  ignoreEvent(): boolean { return true; }
}
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

            const afterMark = itemLine.text.slice(match[0].length);
            const taskMatch = /^ \[([ xX])\] ?/.exec(afterMark);

            const onCursorLine = itemLine.number === cursorLine;
            const tabSize = view.state.tabSize;
            let depth = 0;
            for (const c of match[1]) depth += c === "\t" ? tabSize : 1;
            const gutterEm = 1.0;
            const totalEm  = depth * 0.5 + gutterEm;

            // Apply hanging indent to ALL lines (cursor and non-cursor).
            // Non-cursor: --list-gutter = gutterEm → text-indent = -gutterEm, placing
            //   the bullet/checkbox widget at (totalEm - gutterEm) from the border edge.
            // Cursor: --list-gutter = totalEm → text-indent = -totalEm, so the raw
            //   prefix starts at 0em where tab stops are predictable, minimising the
            //   horizontal jump relative to the rendered text position.
            const cssGutter = onCursorLine ? totalEm : gutterEm;
            decorations.push(
              Decoration.line({
                class: "cm-list-item",
                attributes: { style: `--list-indent: ${totalEm}em; --list-gutter: ${cssGutter}em` },
              }).range(itemLine.from)
            );

            if (!onCursorLine) {
              if (taskMatch) {
                const checked = taskMatch[1] !== " ";
                if (checked) {
                  decorations.push(Decoration.line({ class: "cm-task-checked" }).range(itemLine.from));
                }
                // Replace entire prefix (whitespace + "- " + "[ ] ") with a checkbox widget.
                const prefixTo = itemLine.from + match[0].length + taskMatch[0].length;
                const innerPos = itemLine.from + match[0].length + 2; // skip ' [' to reach checkbox char
                decorations.push(
                  Decoration.replace({ widget: new CheckboxWidget(checked, innerPos) })
                    .range(itemLine.from, prefixTo)
                );
              } else {
                // Replace the full prefix (whitespace + mark char + trailing space)
                // with a BulletWidget of width gutterEm.
                const markCharEnd = itemLine.from + match[0].length;
                const trailingChar = itemLine.text[match[0].length] ?? "";
                const prefixTo = (trailingChar === " " || trailingChar === "\t")
                  ? markCharEnd + 1 : markCharEnd;
                decorations.push(
                  Decoration.replace({ widget: new BulletWidget(gutterEm) })
                    .range(itemLine.from, prefixTo)
                );
              }
            }
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
