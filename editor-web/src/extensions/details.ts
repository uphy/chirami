import { EditorState, Prec, Range, StateEffect, StateField } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  keymap,
  WidgetType,
} from "@codemirror/view";
import { collectHtmlBlocks, cursorLineFromState, transactionCursorRevealChanged, transactionHasWindowActiveEffect } from "./utils";
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

// Decoration.mark() wraps the </details> text in a <span>, making it invisible.
// Unlike Decoration.line(), the .cm-line wrapper is preserved with its natural
// line-height, so ↑ navigation can still reach this position.
// CSS is injected via baseTheme (not an external file) to avoid loading issues.
const detailsCloseMarkDeco = Decoration.mark({ class: "cm-details-close-hidden" });

const detailsTheme = EditorView.baseTheme({
  ".cm-details-close-hidden": {
    opacity: "0",
    pointerEvents: "none",
    userSelect: "none",
  },
});

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
  state: EditorState,
  openBlockTo: number,
  htmlBlocks: Array<{ from: number; to: number }>,
): { from: number; to: number } | null {
  for (const block of htmlBlocks) {
    if (block.from < openBlockTo) continue;
    const text = state.sliceDoc(block.from, block.to).trim();
    if (DETAILS_CLOSE_RE.test(text)) return block;
  }
  return null;
}

function buildDetailsDecorations(state: EditorState): DecorationSet {
  try {
    return _buildDetailsDecorations(state);
  } catch (e) {
    postToSwift({ type: "log", level: "error", message: `DetailsPlugin build error: ${e}` });
    return Decoration.none;
  }
}

function _buildDetailsDecorations(state: EditorState): DecorationSet {
  const cursorLine = cursorLineFromState(state);
  const openState = state.field(detailsOpenState);
  const decorations: Range<Decoration>[] = [];

  const htmlBlocks = collectHtmlBlocks(state);

  for (const block of htmlBlocks) {
    const text = state.sliceDoc(block.from, block.to);
    if (!DETAILS_OPEN_RE.test(text.trimStart())) continue;

    const closeBlock = findCloseTagBlock(state, block.to, htmlBlocks);

    // Raw-edit mode: cursor is anywhere within the full <details>...</details> range.
    // Use closeBlock.from (not .to) so the next line after </details> does NOT
    // trigger raw mode when closeBlock.to includes the trailing newline.
    const rawModeEnd = closeBlock ? closeBlock.from : block.to;
    const rawStartLine = state.doc.lineAt(block.from).number;
    const rawEndLine = state.doc.lineAt(rawModeEnd).number;
    if (cursorLine >= rawStartLine && cursorLine <= rawEndLine) continue;

    if (!closeBlock) continue;

    const summaryMatch = text.match(/<summary[^>]*>([\s\S]*?)<\/summary>/i);
    const summaryText = summaryMatch ? summaryMatch[1].trim() : "";
    const isOpen = openState.get(block.from) ?? false;

    // Replace <details>...<summary> HTMLBlock with SummaryWidget.
    // Decoration.replace() is atomic: cursor can land at its boundary positions,
    // allowing ↑/↓ navigation to enter the block and trigger raw mode.
    decorations.push(
      Decoration.replace({
        widget: new SummaryWidget(summaryText, block.from, block.to, isOpen),
      }).range(block.from, block.to),
    );

    if (!isOpen) {
      // Closed: collapse content between the opening tag block and </details>.
      // Start at block.to (not the line start) to avoid overlapping with the
      // SummaryWidget replace decoration, which would corrupt the decoration set.
      if (block.to < closeBlock.from) {
        decorations.push(
          Decoration.replace({}).range(block.to, closeBlock.from),
        );
      }
    }
    // Both open and closed: hide </details> text via a mark decoration.
    // Decoration.mark() wraps the text in a <span class="cm-details-close-hidden">
    // with opacity:0, while leaving the .cm-line wrapper intact so the height
    // map keeps the full line height for ↑ navigation.
    const closeLine = state.doc.lineAt(closeBlock.from);
    if (closeLine.from < closeLine.to) {
      decorations.push(detailsCloseMarkDeco.range(closeLine.from, closeLine.to));
    }
  }

  if (decorations.length === 0) return Decoration.none;
  return Decoration.set(decorations, true);
}

const detailsDecoField = StateField.define<DecorationSet>({
  create: (state) => buildDetailsDecorations(state),
  update: (deco, tr) => {
    const hasToggle = tr.effects.some((e) => e.is(toggleDetailsEffect));
    if (
      hasToggle ||
      transactionHasWindowActiveEffect(tr) ||
      transactionCursorRevealChanged(tr) ||
      tr.docChanged ||
      tr.startState.selection.main.head !== tr.state.selection.main.head
    ) {
      return buildDetailsDecorations(tr.state);
    }
    return deco.map(tr.changes);
  },
  provide: (field) => EditorView.decorations.from(field),
});

// Returns the full {from, to} range of a <details>...</details> block that
// contains the given position, or null if the position is not inside one.
function findDetailsRangeAt(
  state: EditorState,
  pos: number,
): { from: number; to: number } | null {
  const htmlBlocks = collectHtmlBlocks(state);

  for (const block of htmlBlocks) {
    const text = state.sliceDoc(block.from, block.to);
    if (!DETAILS_OPEN_RE.test(text.trimStart())) continue;
    const closeBlock = findCloseTagBlock(state, block.to, htmlBlocks);
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

  if (!findDetailsRangeAt(view.state, sel.head)) return false;

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
  detailsDecoField,
  detailsTheme,
  Prec.highest(keymap.of([{ key: "Enter", run: enterInDetails }])),
];
