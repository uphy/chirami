import { EditorView, ViewUpdate } from "@codemirror/view";

export function cursorLineNumber(view: EditorView): number {
  if (!view.hasFocus) return -1;
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
  if (update.docChanged || update.viewportChanged || update.focusChanged) return true;
  if (!update.selectionSet) return false;
  // Skip when only the anchor moved (e.g. shift+click with same head position).
  return update.view.state.selection.main.head !== update.startState.selection.main.head;
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
