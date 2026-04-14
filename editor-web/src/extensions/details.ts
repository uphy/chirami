import { Prec, Range, StateEffect, StateField } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  keymap,
  ViewPlugin,
  ViewUpdate,
  WidgetType,
} from "@codemirror/view";
import { collectHtmlBlocks, cursorLineNumber, nodeContainsCursorLine, shouldRebuild } from "./utils";
import { postToSwift } from "../bridge";

const DETAILS_OPEN_RE = /^<details/i;
const DETAILS_CLOSE_RE = /^<\/details>/i;

const toggleDetailsEffect = StateEffect.define<number>();

const detailsOpenState = StateField.define<Map<number, boolean>>({
  create: () => new Map(),
  update: (state, tr) => {
    const hasToggle = tr.effects.some((e) => e.is(toggleDetailsEffect));
    if (!hasToggle && tr.changes.empty) return state;
    const newState = new Map<number, boolean>();
    state.forEach((isOpen, pos) => {
      newState.set(tr.changes.mapPos(pos), isOpen);
    });
    for (const effect of tr.effects) {
      if (effect.is(toggleDetailsEffect)) {
        newState.set(effect.value, !(newState.get(effect.value) ?? false));
      }
    }
    return newState;
  },
});

const detailsHideMark = Decoration.mark({ class: "cm-details-raw" });
const hiddenLineDeco = Decoration.line({ class: "cm-details-hidden-line" });

class SummaryWidget extends WidgetType {
  constructor(
    private summaryText: string,
    private blockPos: number,
    private blockEnd: number,
    private isOpen: boolean,
  ) {
    super();
  }

  eq(other: SummaryWidget): boolean {
    return (
      other.summaryText === this.summaryText &&
      other.blockPos === this.blockPos &&
      other.blockEnd === this.blockEnd &&
      other.isOpen === this.isOpen
    );
  }

  toDOM(view: EditorView): HTMLElement {
    const container = document.createElement("div");
    container.className = `cm-details-summary${this.isOpen ? " cm-details-open" : ""}`;

    const arrow = document.createElement("span");
    arrow.className = "cm-details-arrow";
    arrow.textContent = this.isOpen ? "▼" : "▶";

    const text = document.createElement("span");
    text.className = "cm-details-summary-text";
    text.textContent = this.summaryText;

    container.appendChild(arrow);
    container.appendChild(text);

    container.addEventListener("mousedown", (e) => e.preventDefault());

    arrow.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      view.dispatch({ effects: toggleDetailsEffect.of(this.blockPos) });
    });

    // Text click: enter raw-edit mode by placing the cursor after the opening
    // tag block. The decoration build will skip this block once the cursor is
    // inside the details range, revealing the raw Markdown.
    text.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      view.dispatch({ selection: { anchor: this.blockEnd } });
      view.focus();
    });

    return container;
  }

  ignoreEvent(): boolean {
    return false;
  }
}

function findCloseTagBlock(
  view: EditorView,
  openBlockTo: number,
  htmlBlocks: Array<{ from: number; to: number }>,
): { from: number; to: number } | null {
  for (const block of htmlBlocks) {
    if (block.from < openBlockTo) continue;
    const text = view.state.sliceDoc(block.from, block.to).trim();
    if (DETAILS_CLOSE_RE.test(text)) return block;
  }
  return null;
}

class DetailsPlugin {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate) {
    const hasToggle = update.transactions.some((tr) =>
      tr.effects.some((e) => e.is(toggleDetailsEffect)),
    );
    if (shouldRebuild(update) || hasToggle) {
      this.decorations = this.build(update.view);
    }
  }

  private build(view: EditorView): DecorationSet {
    try {
      return this._build(view);
    } catch (e) {
      postToSwift({ type: "log", level: "error", message: `DetailsPlugin build error: ${e}` });
      return Decoration.none;
    }
  }

  private _build(view: EditorView): DecorationSet {
    const cursorLine = cursorLineNumber(view);
    const openState = view.state.field(detailsOpenState);
    const decorations: Range<Decoration>[] = [];

    // Collect all HTMLBlock nodes across the full document so we can match
    // <details> blocks with their corresponding </details> blocks even when
    // they appear in different viewport ranges.
    const htmlBlocks = collectHtmlBlocks(view);

    for (const block of htmlBlocks) {
      const text = view.state.sliceDoc(block.from, block.to);
      if (!DETAILS_OPEN_RE.test(text.trimStart())) continue;

      const closeBlock = findCloseTagBlock(view, block.to, htmlBlocks);

      // Raw-edit mode: cursor is anywhere within the full <details>...</details> range.
      // Use closeBlock.to as the end so content lines and </details> also keep the editor in raw mode.
      const rawModeEnd = closeBlock ? closeBlock.to : block.to;
      if (nodeContainsCursorLine(view, block.from, rawModeEnd, cursorLine)) continue;

      if (!closeBlock) continue;

      const summaryMatch = text.match(/<summary[^>]*>([\s\S]*?)<\/summary>/i);
      const summaryText = summaryMatch ? summaryMatch[1].trim() : "";
      const isOpen = openState.get(block.from) ?? false;

      // Insert summary widget before the <details> HTMLBlock (side: -1 = before)
      decorations.push(
        Decoration.widget({
          widget: new SummaryWidget(summaryText, block.from, block.to, isOpen),
          side: -1,
        }).range(block.from),
      );
      // Hide the text of the <details>...</summary> HTMLBlock lines.
      // Keep the .cm-line visible (use mark, not line-deco) so SummaryWidget has a container.
      decorations.push(detailsHideMark.range(block.from, block.to));

      if (!isOpen) {
        // Collapse: hide every line from block.to up to and including the </details> line.
        // Decoration.line (not mark) is used so blank lines also lose their height.
        const collapseStartLine = view.state.doc.lineAt(block.to);
        const collapseEndLine = view.state.doc.lineAt(closeBlock.from);
        for (let n = collapseStartLine.number; n <= collapseEndLine.number; n++) {
          decorations.push(hiddenLineDeco.range(view.state.doc.line(n).from));
        }
      } else {
        // Open: only hide the </details> line unless the cursor is on it.
        const cursorInClose = nodeContainsCursorLine(
          view,
          closeBlock.from,
          closeBlock.to,
          cursorLine,
        );
        if (!cursorInClose) {
          const closeLine = view.state.doc.lineAt(closeBlock.from);
          decorations.push(hiddenLineDeco.range(closeLine.from));
        }
      }
    }

    if (decorations.length === 0) return Decoration.none;
    // Let CodeMirror sort — mixing Decoration.line with widget/mark can produce
    // ordering that is tricky to maintain manually.
    return Decoration.set(decorations);
  }
}

const detailsPlugin = ViewPlugin.fromClass(DetailsPlugin, {
  decorations: (v) => v.decorations,
});

// Returns the full {from, to} range of a <details>...</details> block that
// contains the given position, or null if the position is not inside one.
function findDetailsRangeAt(
  view: EditorView,
  pos: number,
): { from: number; to: number } | null {
  const htmlBlocks = collectHtmlBlocks(view);

  for (const block of htmlBlocks) {
    const text = view.state.sliceDoc(block.from, block.to);
    if (!DETAILS_OPEN_RE.test(text.trimStart())) continue;
    const closeBlock = findCloseTagBlock(view, block.to, htmlBlocks);
    if (!closeBlock) continue;
    if (pos >= block.from && pos <= closeBlock.to) {
      return { from: block.from, to: closeBlock.to };
    }
  }
  return null;
}

// Enter inside a <details> block: insert a plain newline preserving the
// current line's leading whitespace only — prevents the HTML language from
// applying XML-style tag indentation to what is actually Markdown content.
function enterInDetails(view: EditorView): boolean {
  const state = view.state;
  const sel = state.selection.main;
  if (!sel.empty) return false;

  if (!findDetailsRangeAt(view, sel.head)) return false;

  const line = state.doc.lineAt(sel.head);
  const indent = /^(\s*)/.exec(line.text)?.[1] ?? "";
  view.dispatch({
    changes: { from: sel.head, to: sel.head, insert: "\n" + indent },
    selection: { anchor: sel.head + 1 + indent.length },
    scrollIntoView: true,
    userEvent: "input",
  });
  return true;
}

export const detailsExtension = [
  detailsOpenState,
  detailsPlugin,
  Prec.highest(keymap.of([{ key: "Enter", run: enterInDetails }])),
];
