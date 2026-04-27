import { foldEffect, syntaxTree, unfoldEffect } from "@codemirror/language";
import { EditorState, StateEffect, StateField, Transaction } from "@codemirror/state";
import { DecorationSet, EditorView, ViewUpdate } from "@codemirror/view";

function isWindowActive(): boolean {
  const getter = (window as Window & { __chiramiWindowActive?: () => boolean }).__chiramiWindowActive;
  return getter ? getter() : true;
}

export const setWindowActiveEffect = StateEffect.define<boolean>();

export const windowActiveField = StateField.define<boolean>({
  create: () => isWindowActive(),
  update: (active, tr) => {
    for (const effect of tr.effects) {
      if (effect.is(setWindowActiveEffect)) {
        return effect.value;
      }
    }
    return active;
  },
});

export function stateWindowActive(state: EditorState): boolean {
  return state.field(windowActiveField, false) ?? true;
}

export function transactionHasWindowActiveEffect(tr: Transaction): boolean {
  return tr.effects.some((effect) => effect.is(setWindowActiveEffect));
}

export function cursorLineNumber(view: EditorView): number {
  if (!view.hasFocus || !isWindowActive()) return -1;
  return view.state.doc.lineAt(view.state.selection.main.head).number;
}

export function nodeContainsCursorLine(
  view: EditorView,
  from: number,
  to: number,
  cursorLine: number
): boolean {
  const startLine = view.state.doc.lineAt(from).number;
  const endLine = view.state.doc.lineAt(to).number;
  return cursorLine >= startLine && cursorLine <= endLine;
}

export function cursorInSpan(cursorPos: number, from: number, to: number): boolean {
  return cursorPos >= from && cursorPos <= to;
}

export function shouldRebuild(update: ViewUpdate): boolean {
  const foldChanged = update.transactions.some((tr) =>
    tr.effects.some((effect) => effect.is(foldEffect) || effect.is(unfoldEffect))
  );
  const windowActiveChanged = update.transactions.some(transactionHasWindowActiveEffect);
  if (foldChanged) return true;
  if (windowActiveChanged) return true;
  if (update.docChanged || update.viewportChanged || update.focusChanged) return true;
  if (!update.selectionSet) return false;
  // Skip when only the anchor moved (e.g. shift+click with same head position).
  return update.view.state.selection.main.head !== update.startState.selection.main.head;
}

export function collectHtmlBlocks(state: EditorState): Array<{ from: number; to: number }> {
  const blocks: Array<{ from: number; to: number }> = [];
  syntaxTree(state).iterate({
    enter: (node) => {
      if (node.name === "HTMLBlock") {
        blocks.push({ from: node.from, to: node.to });
        return false;
      }
    },
  });
  return blocks;
}

export function cursorLineFromState(state: EditorState): number {
  if (!stateWindowActive(state)) return -1;
  return state.doc.lineAt(state.selection.main.head).number;
}

// Factory for decoration StateFields. Rebuilds only when doc changes or
// the cursor head crosses a line boundary — not on every anchor/selection change.
export function makeDecorationField(
  build: (state: EditorState) => DecorationSet,
): StateField<DecorationSet> {
  return StateField.define<DecorationSet>({
    create: build,
    update: (deco, tr) => {
      if (
        transactionHasWindowActiveEffect(tr) ||
        tr.docChanged ||
        tr.startState.selection.main.head !== tr.state.selection.main.head
      ) {
        return build(tr.state);
      }
      return deco.map(tr.changes);
    },
    provide: (field) => EditorView.decorations.from(field),
  });
}

export function debounce<T extends unknown[]>(fn: (...args: T) => void, delay: number): (...args: T) => void {
  let timer: number | null = null;
  return (...args: T) => {
    if (timer !== null) window.clearTimeout(timer);
    timer = window.setTimeout(() => { fn(...args); timer = null; }, delay);
  };
}

export function tryParseJSON<T>(json: string): T | undefined {
  if (!json.trim()) return undefined;
  try {
    return JSON.parse(json) as T;
  } catch {
    return undefined;
  }
}

export interface CodeBlockSizeOptions {
  width?: number;
  height?: number;
}

export function parseCodeBlockInfo(infoString: string): { lang: string; options: CodeBlockSizeOptions } {
  const parts = infoString.trim().split(/\s+/);
  const lang = (parts[0] ?? "").toLowerCase();
  const options: CodeBlockSizeOptions = {};

  for (const part of parts.slice(1)) {
    const eqIdx = part.indexOf("=");
    if (eqIdx === -1) continue;
    const key = part.slice(0, eqIdx);
    const value = part.slice(eqIdx + 1);
    if ((key === "width" || key === "height") && value) {
      const num = parseInt(value, 10);
      if (!isNaN(num) && num > 0) options[key] = num;
    }
  }

  return { lang, options };
}

export function applySizeOptions(el: HTMLElement, opts: CodeBlockSizeOptions): void {
  if (opts.width) el.style.setProperty("--cm-block-width", `${opts.width}px`);
  if (opts.height) el.style.setProperty("--cm-block-height", `${opts.height}px`);
}

export function sizeOptionsEq(a: CodeBlockSizeOptions, b: CodeBlockSizeOptions): boolean {
  return a.width === b.width && a.height === b.height;
}
