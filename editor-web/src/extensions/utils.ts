import { EditorView, ViewUpdate } from "@codemirror/view";

export function cursorLineNumber(view: EditorView): number {
  return view.state.doc.lineAt(view.state.selection.main.head).number;
}

export function shouldRebuild(update: ViewUpdate): boolean {
  if (update.docChanged || update.viewportChanged) return true;
  if (update.selectionSet) {
    const newLine = update.view.state.doc.lineAt(update.view.state.selection.main.head).number;
    const oldLine = update.startState.doc.lineAt(update.startState.selection.main.head).number;
    return newLine !== oldLine;
  }
  return false;
}

export function debounce<T extends unknown[]>(fn: (...args: T) => void, delay: number): (...args: T) => void {
  let timer: number | null = null;
  return (...args: T) => {
    if (timer !== null) window.clearTimeout(timer);
    timer = window.setTimeout(() => { fn(...args); timer = null; }, delay);
  };
}
