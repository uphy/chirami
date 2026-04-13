import { syntaxTree } from "@codemirror/language";
import { EditorSelection } from "@codemirror/state";
import { EditorView, KeyBinding } from "@codemirror/view";
import { insertNewlineContinueMarkup } from "@codemirror/lang-markdown";
import { indentMore, indentLess } from "@codemirror/commands";
import { postToSwift } from "../bridge";

// Wraps insertNewlineContinueMarkup to prevent spurious blank lines in tight lists.
// CodeMirror's nonTightList heuristic sometimes misclassifies long (visually
// wrapped) lines as loose, inserting "\n\n- " instead of "\n- ".
// This handler checks if the list was already loose before the keypress; if not
// and a blank line was inserted, it removes the extra newline.
function tightListEnter(view: EditorView): boolean {
  const state = view.state;
  const head = state.selection.main.head;
  const headLine = state.doc.lineAt(head);

  // Was the line immediately after the cursor already blank? (= existing loose list)
  const nextLineNum = headLine.number + 1;
  const wasLoose =
    nextLineNum <= state.doc.lines &&
    state.doc.line(nextLineNum).text.trim() === "";

  const result = insertNewlineContinueMarkup(view);
  if (!result) return false;

  // If the list was tight and a blank line was unexpectedly inserted, remove it.
  if (!wasLoose) {
    const afterState = view.state;
    const afterHead = afterState.selection.main.head;
    const afterLine = afterState.doc.lineAt(afterHead);

    if (afterLine.number > 1) {
      const prevLine = afterState.doc.line(afterLine.number - 1);
      if (prevLine.text === "") {
        view.dispatch({
          changes: { from: prevLine.from, to: prevLine.to + 1 },
          selection: { anchor: afterHead - (prevLine.length + 1) },
        });
      }
    }
  }

  return true;
}

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

// Indents a list item and immediately places the cursor after the list mark.
// Without this, indentMore puts the cursor between \t and "-" (before the mark),
// then livePreview's cm-list-raw-hanging decoration changes the layout a frame
// later, making the cursor visually jump to after "- ". This eliminates that flicker
// by moving the cursor to the content start in the same transaction as the indent.
function indentListItem(view: EditorView): boolean {
  const state = view.state;
  const sel = state.selection.main;
  if (!sel.empty) return false;

  const line = state.doc.lineAt(sel.head);
  const match = /^([ \t]*)([-*+])([ \t]+)/.exec(line.text);
  if (!match) return false;

  const contentStart = line.from + match[0].length;
  const cursorBeforeContent = sel.head < contentStart;

  const result = indentMore(view);
  if (!result) return false;

  if (cursorBeforeContent) {
    const newState = view.state;
    const newLine = newState.doc.lineAt(newState.selection.main.head);
    const newMatch = /^([ \t]*)([-*+])([ \t]+)/.exec(newLine.text);
    if (newMatch) {
      view.dispatch({
        selection: EditorSelection.cursor(newLine.from + newMatch[0].length),
        scrollIntoView: true,
      });
    }
  }

  return true;
}

// Dedents a list item and places the cursor after the list mark.
// Mirrors indentListItem to avoid the same visual flicker on Shift+Tab.
function dedentListItem(view: EditorView): boolean {
  const state = view.state;
  const sel = state.selection.main;
  if (!sel.empty) return false;

  const line = state.doc.lineAt(sel.head);
  const match = /^([ \t]*)([-*+])([ \t]+)/.exec(line.text);
  if (!match) return false;

  const contentStart = line.from + match[0].length;
  const cursorBeforeContent = sel.head < contentStart;

  const result = indentLess(view);
  if (!result) return false;

  if (cursorBeforeContent) {
    const newState = view.state;
    const newLine = newState.doc.lineAt(newState.selection.main.head);
    const newMatch = /^([ \t]*)([-*+])([ \t]+)/.exec(newLine.text);
    if (newMatch) {
      view.dispatch({
        selection: EditorSelection.cursor(newLine.from + newMatch[0].length),
        scrollIntoView: true,
      });
    }
  }

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

export const tightListEnterKeymap: KeyBinding[] = [
  { key: "Enter", run: tightListEnter },
];

export const chiramiKeymap: KeyBinding[] = [
  { key: "Tab", run: indentListItem, shift: dedentListItem },
  { key: "ArrowDown", run: (view) => moveVerticalOnListLine(view, 1) },
  { key: "ArrowUp", run: (view) => moveVerticalOnListLine(view, -1) },
  { key: "Mod-b", run: (view) => wrapSelection(view, "**") },
  { key: "Mod-i", run: (view) => wrapSelection(view, "*") },
  { key: "Mod-l", run: toggleTaskAtCursor },
  { key: "Mod-Enter", run: openLinkAtCursor },
];
