import { foldedRanges, syntaxTree } from "@codemirror/language";
import { Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
  WidgetType,
} from "@codemirror/view";
import { INLINE_FORMAT_MARK_NODES, INLINE_LINK_MARK_NODES, isStandaloneURLNode } from "./inlineMarkdown";
import { cursorInSpan, cursorLineNumber, nodeContainsCursorLine, parseCodeBlockInfo, shouldRebuild } from "./utils";

// Markdown syntax marks to hide on non-cursor lines.
// ListMark ("-", "*", "+") is handled separately below with bullet replacement.
// HeaderMark ("# ") is handled separately below to also hide the trailing space.
// Marks that go raw whenever cursor is anywhere inside the enclosing construct.
// EmphasisMark/CodeMark/StrikethroughMark: opening+closing fence go raw together.
// CodeInfo: language tag is shown whenever cursor is inside the fenced code block.
const PARENT_SPAN_MARKS = new Set([...INLINE_FORMAT_MARK_NODES, "CodeInfo"]);

// Link/Image marks are handled as a group using the parent node span,
// so all marks within a link go raw together when cursor touches any part of it.
const LINK_MARK_NODES = INLINE_LINK_MARK_NODES;

const HIDDEN_DECORATION = Decoration.replace({ inclusive: false });
const CLICKABLE_LINK = Decoration.mark({ class: "cm-clickable-link" });
// Fixed-width box around an ordered list marker ("1. "). Width comes from
// --list-gutter on the line, set alongside the cm-list-item decoration.
const ORDERED_MARKER = Decoration.mark({ class: "cm-ordered-marker" });

const LIST_MARK_RE   = /^[-*+](?=[ \t])/;
// Ordered list marker: "1." / "1)" followed by whitespace.
const ORDERED_MARK_RE = /^\d{1,9}[.)](?=[ \t])/;
const TASK_MARK_RE   = /^ \[([ xX])\](?=[ \t])/;
const HEADING_NODE_RE = /^(ATXHeading|SetextHeading)[1-6]$/;
const BQ_PREFIX_RE   = /^(>\s?)+/;
const GUTTER_EM      = 1.0;
// Task items use a wider gutter: 16px checkbox + ~10px gap (design gap: 10).
// At 13px font: 1.9em ≈ 24.7px → ~8.7px gap. At 14px: 1.9em = 26.6px → ~10.6px gap.
const TASK_GUTTER_EM = 1.9;

// Using an inline-block span (same as BulletWidget) ensures the widget occupies
// exactly TASK_GUTTER_EM regardless of the checkbox's pixel size, so wrapped
// lines align with text start.
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
    const span = document.createElement("span");
    span.className = "cm-checkbox-gutter";
    span.style.width = `${TASK_GUTTER_EM}em`;

    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = this.checked;
    input.tabIndex = -1;
    span.appendChild(input);

    // Dispatch on mousedown rather than click: when clicking an unfocused window
    // with the cursor already in the task prefix, focus acquisition triggers a
    // decoration rebuild that detaches this element before `click` can fire.
    // Firing on mousedown ensures the dispatch reaches the view while the DOM
    // element is still live. preventDefault keeps the cursor from moving into
    // the prefix and keeps CodeMirror from handling the event (ignoreEvent=true
    // suppresses CM's own cursor-placement logic for this widget entirely).
    span.addEventListener("mousedown", (e) => {
      e.preventDefault();
      const nextChar = this.checked ? " " : "x";
      view.dispatch({
        changes: { from: this.innerPos, to: this.innerPos + 1, insert: nextChar },
      });
    });

    return span;
  }

  ignoreEvent(): boolean {
    // Let the widget own its events entirely; CodeMirror should not place the
    // cursor or perform any other handling when the gutter span is clicked.
    return true;
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

type FoldRange = { from: number; to: number };

function isInFoldedContent(pos: number, ranges: readonly FoldRange[]): boolean {
  for (const range of ranges) {
    if (pos <= range.from) return false;
    if (pos <= range.to) return true;
  }
  return false;
}

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
  private pendingRebuild = false;

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate) {
    const needsRebuild = shouldRebuild(update);
    // view.composing misses some IME events; transaction events cover the gap.
    const isComposing =
      update.view.composing ||
      update.transactions.some(
        (tr) => tr.isUserEvent("input.type.compose") || tr.isUserEvent("input.compose"),
      );
    if (isComposing) {
      // Keep the previous preview visible during IME composition. Dropping all
      // decorations forces the whole viewport back to raw Markdown, which is
      // visually disruptive for lists and can remain stuck until the next
      // cursor move if composition teardown races the rebuild signal.
      this.pendingRebuild = this.pendingRebuild || needsRebuild || update.docChanged;
      if (update.docChanged && this.decorations !== Decoration.none) {
        this.decorations = this.decorations.map(update.changes);
      }
      return;
    }
    if (this.pendingRebuild || needsRebuild) {
      this.pendingRebuild = false;
      this.decorations = this.build(update.view);
    }
  }

  private build(view: EditorView): DecorationSet {
    const cursorLine = cursorLineNumber(view);
    // Treat the cursor as absent while the window is inactive so every construct
    // falls back to rendered preview, not just line-based cases.
    const cursorPos  = cursorLine === -1 ? -1 : view.state.selection.main.head;
    const decorations: Range<Decoration>[] = [];
    const tree = syntaxTree(view.state);
    const hiddenRanges: FoldRange[] = [];
    foldedRanges(view.state).between(0, view.state.doc.length, (from, to) => {
      hiddenRanges.push({ from, to });
    });
    const processedCodeLines = new Set<number>();
    const processedListLineStarts = new Set<number>();
    const calloutReplacedLineStarts = new Set<number>();

    for (const { from, to } of view.visibleRanges) {
      tree.iterate({
        from,
        to,
        enter: (node) => {
          if (isInFoldedContent(node.from, hiddenRanges)) {
            return false;
          }

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
                if (isInFoldedContent(line.from, hiddenRanges)) continue;
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
                if (isInFoldedContent(line.from, hiddenRanges)) continue;
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
              if (isInFoldedContent(line.from, hiddenRanges)) continue;
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

          // Heading lines get a level class so CSS can add vertical breathing
          // room. Without it a heading sits flush against the surrounding text
          // and the hierarchy depends on the author leaving blank lines.
          if (HEADING_NODE_RE.test(node.name)) {
            const level = Number(node.name.slice(-1));
            const headingLine = view.state.doc.lineAt(node.from);
            decorations.push(
              Decoration.line({ class: `cm-heading cm-heading-${level}` }).range(headingLine.from)
            );
            return; // continue into children so HeaderMark is still processed
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
            const firstVisitForLine = !processedListLineStarts.has(itemLine.from);
            if (firstVisitForLine) {
              processedListLineStarts.add(itemLine.from);
            }
            // node.from points to the list marker character ('-', '*', '+').
            // Any leading indent spaces come before node.from on the same line.
            const nodeOffset = node.from - itemLine.from;
            const lineText = itemLine.text;
            const textFromNode = lineText.slice(nodeOffset);
            const match = LIST_MARK_RE.exec(textFromNode);
            const orderedMatch = match ? null : ORDERED_MARK_RE.exec(textFromNode);
            if (!match && !orderedMatch) return;

            const afterMark = textFromNode.slice(1);
            const taskMatch = match ? TASK_MARK_RE.exec(afterMark) : null;

            const onCursorLine = itemLine.number === cursorLine;
            const tabSize = view.state.tabSize;

            // Compute depth from indent spaces before node.from, excluding any
            // blockquote prefix (">" + optional space) at the start of the line.
            const charsBeforeMarker = lineText.slice(0, nodeOffset);
            const bqPrefixMatch = BQ_PREFIX_RE.exec(charsBeforeMarker);
            const bqPrefixLen = bqPrefixMatch ? bqPrefixMatch[0].length : 0;
            const indentText = charsBeforeMarker.slice(bqPrefixLen);
            let depth = 0;
            for (const c of indentText) depth += c === "\t" ? tabSize : 1;

            const effectiveGutterEm = taskMatch ? TASK_GUTTER_EM : GUTTER_EM;
            // Bullets/tasks replace the marker with a fixed-width widget, so the
            // gutter is a constant em value. Ordered items keep their number
            // visible, so the gutter is sized in `ch` to the marker's own width
            // ("10." needs more room than "1.").
            const gutter = orderedMatch
              ? `${orderedMatch[0].length + 1}ch`
              : `${effectiveGutterEm}em`;
            const totalIndent = `calc(${depth * 0.5}em + ${gutter})`;

            // Use node.from (not itemLine.from) as the base so positions are correct
            // both inside and outside blockquotes.
            let prefixTo: number;
            if (taskMatch) {
              prefixTo = node.from + 1 + taskMatch[0].length + 1;
            } else if (orderedMatch) {
              prefixTo = node.from + orderedMatch[0].length + 1;
            } else {
              prefixTo = node.from + 2;
            }

            // Cursor lines: --list-gutter = the full indent so the raw prefix starts at 0
            // (predictable tab stops). Other positions: the marker gutter so rendered text aligns normally.
            const cursorInPrefix = onCursorLine && cursorPos >= itemLine.from && cursorPos < prefixTo;
            const cssGutter = cursorInPrefix ? totalIndent : gutter;
            if (firstVisitForLine) {
              decorations.push(
                Decoration.line({
                  class: "cm-list-item",
                  attributes: { style: `--list-indent: ${totalIndent}; --list-gutter: ${cssGutter}` },
                }).range(itemLine.from)
              );
            }

            if (firstVisitForLine && !cursorInPrefix) {
              // Hide indent spaces before the marker (after any blockquote prefix).
              // This keeps the bullet/checkbox widget visually at the correct indent
              // while padding-left controls the wrap-line alignment.
              const indentStartPos = itemLine.from + bqPrefixLen;
              if (indentStartPos < node.from) {
                decorations.push(HIDDEN_DECORATION.range(indentStartPos, node.from));
              }

              if (taskMatch) {
                const checked = taskMatch[1] !== " ";
                if (checked) {
                  decorations.push(Decoration.line({ class: "cm-task-checked" }).range(itemLine.from));
                }
                const innerPos = node.from + 3; // skip '-', ' ', '[' to reach checkbox char
                // Keep the task prefix boundary at contentStart so Enter -> Tab on
                // empty task items leaves the caret after "- [ ] " rather than
                // snapping before the rendered checkbox widget.
                decorations.push(HIDDEN_DECORATION.range(node.from, prefixTo));
                decorations.push(
                  Decoration.widget({ widget: new CheckboxWidget(checked, innerPos), side: -1 })
                    .range(prefixTo)
                );
              } else if (orderedMatch) {
                // Keep the number as text, but box it into exactly one gutter
                // width so wrapped lines line up with the item text.
                decorations.push(
                  ORDERED_MARKER.range(node.from, prefixTo)
                );
              } else {
                decorations.push(
                  Decoration.replace({ widget: new BulletWidget(GUTTER_EM) })
                    .range(node.from, prefixTo)
                );
              }
            }
            return;
          }

          if (node.name === "WikiLink") {
            // Cursor inside: leave the raw `[[..]]` visible for editing.
            if (cursorInSpan(cursorPos, node.from, node.to)) return false;
            decorations.push(CLICKABLE_LINK.range(node.from, node.to));
            // Hide the opening/closing brackets.
            decorations.push(HIDDEN_DECORATION.range(node.from, node.from + 2));
            decorations.push(HIDDEN_DECORATION.range(node.to - 2, node.to));
            // `[[target|alias]]` shows only the alias: hide "target|".
            const inner = view.state.sliceDoc(node.from + 2, node.to - 2);
            const pipe = inner.indexOf("|");
            if (pipe >= 0) {
              decorations.push(
                HIDDEN_DECORATION.range(node.from + 2, node.from + 2 + pipe + 1)
              );
            }
            return false;
          }

          if (LINK_MARK_NODES.has(node.name)) {
            if (isStandaloneURLNode(node.node)) {
              if (cursorInSpan(cursorPos, node.from, node.to)) return;
              decorations.push(CLICKABLE_LINK.range(node.from, node.to));
              return;
            }

            const parent = node.node.parent;
            const spanFrom = parent?.from ?? node.from;
            const spanTo   = parent?.to   ?? node.to;
            if (cursorInSpan(cursorPos, spanFrom, spanTo)) return;
            if (node.name === "URL") {
              decorations.push(CLICKABLE_LINK.range(spanFrom, spanTo));
            }
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
