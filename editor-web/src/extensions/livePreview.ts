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
import { cursorInSpan, cursorLineNumber, nodeContainsCursorLine, parseCodeBlockInfo, shouldRebuild } from "./utils";

// Markdown syntax marks to hide on non-cursor lines.
// ListMark ("-", "*", "+") is handled separately below with bullet replacement.
// HeaderMark ("# ") is handled separately below to also hide the trailing space.
// Marks that go raw whenever cursor is anywhere inside the enclosing construct.
// EmphasisMark/CodeMark/StrikethroughMark: opening+closing fence go raw together.
// CodeInfo: language tag is shown whenever cursor is inside the fenced code block.
const PARENT_SPAN_MARKS = new Set([
  "EmphasisMark",
  "CodeMark",
  "CodeInfo",
  "StrikethroughMark",
]);

// Link/Image marks are handled as a group using the parent node span,
// so all marks within a link go raw together when cursor touches any part of it.
const LINK_MARK_NODES = new Set(["LinkMark", "URL"]);

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
const HR_DECORATION = Decoration.mark({ class: "chirami-hr" });

const CODE_BLOCK_LINE       = Decoration.line({ class: "cm-code-block-line" });
const CODE_BLOCK_LINE_FIRST = Decoration.line({ class: "cm-code-block-line cm-code-block-first" });
const CODE_BLOCK_LINE_LAST  = Decoration.line({ class: "cm-code-block-line cm-code-block-last" });
const CODE_BLOCK_LINE_ONLY  = Decoration.line({ class: "cm-code-block-line cm-code-block-first cm-code-block-last" });
const QUOTE_LINE            = Decoration.line({ class: "cm-quote" });

// Obsidian callout: map type → color category
const CALLOUT_CATEGORY: Record<string, string> = {
  note: "note", info: "note",
  abstract: "abstract", summary: "abstract", tldr: "abstract",
  tip: "tip", hint: "tip", important: "tip",
  success: "success", check: "success", done: "success",
  question: "question", help: "question", faq: "question",
  warning: "warning", caution: "warning", attention: "warning",
  failure: "failure", fail: "failure", missing: "failure",
  danger: "danger", error: "danger", bug: "danger",
  example: "example",
  quote: "quote", cite: "quote",
};

const CALLOUT_ICONS: Record<string, string> = {
  note:     "✎",
  abstract: "≡",
  tip:      "✦",
  success:  "✓",
  question: "?",
  warning:  "⚠",
  failure:  "✗",
  danger:   "⚡",
  example:  "⊕",
  quote:    "❝",
};

const BLOCKQUOTE_CONTENT_RE = /^>\s*(.*)/;
const CALLOUT_HEADER_RE     = /^\[!([\w-]+)\][ \t]*(.*)/;

class CalloutTitleWidget extends WidgetType {
  constructor(
    private calloutType: string,
    private title: string,
  ) { super(); }

  eq(other: CalloutTitleWidget): boolean {
    return other.calloutType === this.calloutType && other.title === this.title;
  }

  toDOM(): HTMLElement {
    const category = CALLOUT_CATEGORY[this.calloutType] ?? "note";
    const el = document.createElement("span");
    el.className = "cm-callout-title";

    const icon = document.createElement("span");
    icon.className = "cm-callout-icon";
    icon.textContent = CALLOUT_ICONS[category] ?? "ℹ";

    const text = document.createElement("span");
    text.textContent = this.title || (this.calloutType.charAt(0).toUpperCase() + this.calloutType.slice(1));

    el.appendChild(icon);
    el.appendChild(text);
    return el;
  }

  ignoreEvent(): boolean { return false; }
}


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
    const cursorPos  = view.state.selection.main.head;
    const decorations: Range<Decoration>[] = [];
    const tree = syntaxTree(view.state);
    const processedCodeLines = new Set<number>();
    const calloutReplacedLineStarts = new Set<number>();

    for (const { from, to } of view.visibleRanges) {
      tree.iterate({
        from,
        to,
        enter: (node) => {
          if (node.name === "Blockquote") {
            const firstLine    = view.state.doc.lineAt(node.from);
            const startLineNum = view.state.doc.lineAt(Math.max(node.from, from)).number;
            const endLineNum   = view.state.doc.lineAt(Math.min(node.to, to)).number;

            // Detect Obsidian callout: first line matches "> [!TYPE] optional title"
            const firstContent = BLOCKQUOTE_CONTENT_RE.exec(firstLine.text)?.[1] ?? "";
            const calloutMatch = CALLOUT_HEADER_RE.exec(firstContent);

            if (calloutMatch) {
              const calloutType = calloutMatch[1].toLowerCase();
              const calloutTitle = calloutMatch[2].trim();
              const category = CALLOUT_CATEGORY[calloutType] ?? "note";
              const cursorOnHeader = cursorLine === firstLine.number;

              const fullEndLineNum = view.state.doc.lineAt(node.to).number;
              for (let lineNum = startLineNum; lineNum <= endLineNum; lineNum++) {
                const line = view.state.doc.line(lineNum);
                const isHeader = lineNum === firstLine.number;
                const isLast   = lineNum === fullEndLineNum;
                const extra    = isHeader && isLast ? " cm-callout-header cm-callout-last"
                               : isHeader           ? " cm-callout-header"
                               : isLast             ? " cm-callout-last"
                               :                      "";
                decorations.push(
                  Decoration.line({ class: `cm-callout cm-callout-${category}${extra}` })
                    .range(line.from)
                );
              }

              // Full line range avoids adjacent-decoration conflicts with QuoteMark HIDDEN_DECORATION.
              if (!cursorOnHeader && firstLine.number >= startLineNum && firstLine.number <= endLineNum) {
                calloutReplacedLineStarts.add(firstLine.from);
                decorations.push(
                  Decoration.replace({ widget: new CalloutTitleWidget(calloutType, calloutTitle) })
                    .range(firstLine.from, firstLine.to)
                );
              }
            } else {
              for (let lineNum = startLineNum; lineNum <= endLineNum; lineNum++) {
                const line = view.state.doc.line(lineNum);
                decorations.push(QUOTE_LINE.range(line.from));
              }
            }
            return; // Continue into children for QuoteMark handling
          }

          if (node.name === "FencedCode") {
            // mermaid/tldraw/excalidraw own their rendered widgets; skip duplicate line decorations.
            const codeInfoNode = node.node.getChild("CodeInfo");
            if (codeInfoNode) {
              const { lang } = parseCodeBlockInfo(
                view.state.sliceDoc(codeInfoNode.from, codeInfoNode.to)
              );
              if (lang === "mermaid" || lang === "tldraw" || lang === "excalidraw") return false;
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
            const headingParent = node.node.parent;
            const hSpanFrom = headingParent?.from ?? node.from;
            const hSpanTo   = headingParent?.to   ?? node.to;
            if (cursorInSpan(cursorPos, hSpanFrom, hSpanTo)) return;
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
            // node.from points to the actual list marker in the document, which may be
            // after a blockquote prefix ("> "). Slice from node.from so the regex works
            // correctly regardless of whether the item is inside a blockquote.
            const nodeOffset = node.from - itemLine.from;
            const textFromNode = itemLine.text.slice(nodeOffset);
            const match = /^([ \t]*)([-*+])/.exec(textFromNode);
            if (!match) return;

            const afterMark = textFromNode.slice(match[0].length);
            const taskMatch = /^ \[([ xX])\] ?/.exec(afterMark);

            const onCursorLine = itemLine.number === cursorLine;
            const tabSize = view.state.tabSize;
            let depth = 0;
            for (const c of match[1]) depth += c === "\t" ? tabSize : 1;
            const gutterEm = 1.0;
            const totalEm  = depth * 0.5 + gutterEm;

            // Use node.from (not itemLine.from) as the base so positions are correct
            // both inside and outside blockquotes.
            let prefixTo: number;
            if (taskMatch) {
              prefixTo = node.from + match[0].length + taskMatch[0].length;
            } else {
              const markCharEnd = node.from + match[0].length;
              const trailingChar = textFromNode[match[0].length] ?? "";
              prefixTo = (trailingChar === " " || trailingChar === "\t") ? markCharEnd + 1 : markCharEnd;
            }

            // Cursor lines: --list-gutter = totalEm so the raw prefix starts at 0em
            // (predictable tab stops). Other positions: gutterEm so rendered text aligns normally.
            const cursorInPrefix = onCursorLine && cursorPos >= itemLine.from && cursorPos < prefixTo;
            const cssGutter = cursorInPrefix ? totalEm : gutterEm;
            decorations.push(
              Decoration.line({
                class: "cm-list-item",
                attributes: { style: `--list-indent: ${totalEm}em; --list-gutter: ${cssGutter}em` },
              }).range(itemLine.from)
            );

            if (!cursorInPrefix) {
              if (taskMatch) {
                const checked = taskMatch[1] !== " ";
                if (checked) {
                  decorations.push(Decoration.line({ class: "cm-task-checked" }).range(itemLine.from));
                }
                // Replace prefix (whitespace + "- " + "[ ]") with a checkbox widget.
                // Exclude the trailing space from the widget range so it stays visible.
                const innerPos = node.from + match[0].length + 2; // skip ' [' to reach checkbox char
                const widgetEnd = taskMatch[0].endsWith(" ") ? prefixTo - 1 : prefixTo;
                decorations.push(
                  Decoration.replace({ widget: new CheckboxWidget(checked, innerPos) })
                    .range(node.from, widgetEnd)
                );
              } else {
                // Replace the full prefix (whitespace + mark char + trailing space)
                // with a BulletWidget of width gutterEm.
                decorations.push(
                  Decoration.replace({ widget: new BulletWidget(gutterEm) })
                    .range(node.from, prefixTo)
                );
              }
            }
            return;
          }

          if (LINK_MARK_NODES.has(node.name)) {
            const parent = node.node.parent;
            const spanFrom = parent?.from ?? node.from;
            const spanTo   = parent?.to   ?? node.to;
            // Also show raw when cursor is on the same line (e.g. "[!NOTE]" in callout headers).
            if (cursorInSpan(cursorPos, spanFrom, spanTo)) return;
            if (view.state.doc.lineAt(node.from).number === cursorLine) return;
            decorations.push(HIDDEN_DECORATION.range(node.from, node.to));
            return;
          }

          if (PARENT_SPAN_MARKS.has(node.name)) {
            const parent = node.node.parent;
            const spanFrom = parent?.from ?? node.from;
            const spanTo   = parent?.to   ?? node.to;
            if (cursorInSpan(cursorPos, spanFrom, spanTo)) return;
            decorations.push(HIDDEN_DECORATION.range(node.from, node.to));
            return;
          }

          if (node.name === "HorizontalRule") {
            if (view.state.doc.lineAt(node.from).number === cursorLine) return;
            decorations.push(HR_DECORATION.range(node.from, node.to));
            return;
          }

          // QuoteMark (">") goes raw when cursor is on the same blockquote line.
          // Skip if the line is fully replaced by a callout widget to avoid overlap.
          if (node.name === "QuoteMark") {
            const lineStart = view.state.doc.lineAt(node.from).from;
            if (calloutReplacedLineStarts.has(lineStart)) return;
            if (nodeContainsCursorLine(view, node.from, node.to, cursorLine)) return;
            decorations.push(HIDDEN_DECORATION.range(node.from, node.to));
          }
        },
      });
    }

    return Decoration.set(decorations, true);
  }
}

export const livePreview = ViewPlugin.fromClass(LivePreviewPlugin, {
  decorations: (v) => v.decorations,
});
