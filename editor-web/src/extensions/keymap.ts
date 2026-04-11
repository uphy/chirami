import { syntaxTree } from "@codemirror/language";
import { EditorSelection } from "@codemirror/state";
import { EditorView, KeyBinding } from "@codemirror/view";
import { postToSwift } from "../bridge";

function wrapSelection(view: EditorView, marker: string): boolean {
  const changes = view.state.changeByRange((range) => {
    const text = view.state.sliceDoc(range.from, range.to);
    const wrapped = `${marker}${text}${marker}`;
    return {
      changes: { from: range.from, to: range.to, insert: wrapped },
      range: EditorSelection.range(
        range.from + marker.length,
        range.to + marker.length,
      ),
    };
  });
  view.dispatch(view.state.update(changes, { scrollIntoView: true }));
  return true;
}

function toggleTaskAtCursor(view: EditorView): boolean {
  const line = view.state.doc.lineAt(view.state.selection.main.head);
  const match = line.text.match(/^(\s*[-*+]\s+)\[( |x)\]/i);
  if (!match) return false;
  const bracketStart = line.from + match[1].length + 1;
  const currentChar = match[2];
  const nextChar = currentChar === " " ? "x" : " ";
  view.dispatch({
    changes: { from: bracketStart, to: bracketStart + 1, insert: nextChar },
  });
  return true;
}

function hasListMarkOnLine(view: EditorView, from: number, to: number): boolean {
  let found = false;
  syntaxTree(view.state).iterate({
    from,
    to,
    enter: (node) => {
      if (node.name === "ListMark") {
        found = true;
        return false;
      }
    },
  });
  return found;
}

function moveVerticalOnListLine(view: EditorView, dir: 1 | -1): boolean {
  const state = view.state;
  const sel = state.selection.main;
  if (!sel.empty) return false;

  const curLine = state.doc.lineAt(sel.head);
  if (!hasListMarkOnLine(view, curLine.from, curLine.to)) return false;

  const targetLineNum = curLine.number + dir;
  if (targetLineNum < 1 || targetLineNum > state.doc.lines) return false;

  const targetLine = state.doc.line(targetLineNum);
  const col = sel.head - curLine.from;
  const targetPos = targetLine.from + Math.min(col, targetLine.length);

  view.dispatch({
    selection: EditorSelection.cursor(targetPos),
    scrollIntoView: true,
  });
  return true;
}

function openLinkAtCursor(view: EditorView): boolean {
  const pos = view.state.selection.main.head;
  const tree = syntaxTree(view.state);
  let node = tree.resolve(pos, -1);

  // Walk up the tree looking for a Link or URL node
  for (let n: typeof node | null = node; n; n = n.parent) {
    if (n.name === "Link") {
      // Find the URL child within the link
      let child = n.firstChild;
      while (child) {
        if (child.name === "URL") {
          const url = view.state.sliceDoc(child.from, child.to);
          postToSwift({ type: "openLink", url });
          return true;
        }
        child = child.nextSibling;
      }
    }
    if (n.name === "URL") {
      const url = view.state.sliceDoc(n.from, n.to);
      postToSwift({ type: "openLink", url });
      return true;
    }
  }
  return false;
}

export const chiramiKeymap: KeyBinding[] = [
  { key: "ArrowDown", run: (view) => moveVerticalOnListLine(view, 1) },
  { key: "ArrowUp", run: (view) => moveVerticalOnListLine(view, -1) },
  { key: "Mod-b", run: (view) => wrapSelection(view, "**") },
  { key: "Mod-i", run: (view) => wrapSelection(view, "*") },
  { key: "Mod-l", run: toggleTaskAtCursor },
  { key: "Mod-Enter", run: openLinkAtCursor },
];
