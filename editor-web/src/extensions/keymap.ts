import { syntaxTree, indentUnit, foldCode, unfoldCode, foldAll, unfoldAll } from "@codemirror/language";
import { EditorSelection } from "@codemirror/state";
import { EditorView, KeyBinding } from "@codemirror/view";
import { insertNewlineContinueMarkupCommand } from "@codemirror/lang-markdown";
import { postToSwift } from "../bridge";

// Always dedent on empty list items instead of converting to a loose list.
const continueMarkup = insertNewlineContinueMarkupCommand({ nonTightLists: false });

const LIST_ITEM_RE = /^([ \t]*)([-*+])([ \t]+)/;
const TASK_ITEM_RE = /^\[(?: |x|X)\][ \t]*/;
const IME_COMPOSING_CLASS = "chirami-ime-composing";

function isImeAcceptEnter(event: KeyboardEvent): boolean {
  if (event.key !== "Enter") return false;
  // WebKit on macOS can dispatch the Enter keydown that confirms IME input
  // after compositionend, making event.isComposing/view.composing unreliable.
  return event.isComposing || event.keyCode === 229;
}

function listContentStartOffset(lineText: string): number | null {
  const match = LIST_ITEM_RE.exec(lineText);
  if (!match) return null;
  const trailingText = lineText.slice(match[0].length);
  const taskMatch = TASK_ITEM_RE.exec(trailingText);
  return match[0].length + (taskMatch?.[0].length ?? 0);
}

function normalizeCursorToListContent(view: EditorView): void {
  const head = view.state.selection.main.head;
  const line = view.state.doc.lineAt(head);
  const contentOffset = listContentStartOffset(line.text);
  if (contentOffset === null) return;

  const contentStart = line.from + contentOffset;
  if (head >= contentStart) return;

  view.dispatch({
    selection: EditorSelection.cursor(contentStart),
    scrollIntoView: true,
  });
}

function isInListItemContext(view: EditorView, pos: number, lineFrom: number): boolean {
  for (let node = syntaxTree(view.state).resolveInner(pos, -1); node; node = node.parent) {
    if (node.name !== "ListItem") continue;
    return view.state.doc.lineAt(node.from).from === lineFrom;
  }
  return false;
}

function splitListItemAtContentStart(view: EditorView): boolean {
  const state = view.state;
  const head = state.selection.main.head;
  const line = state.doc.lineAt(head);
  const contentOffset = listContentStartOffset(line.text);
  if (contentOffset === null) return false;

  const contentStart = line.from + contentOffset;
  const contentText = line.text.slice(contentOffset);
  if (contentText.length === 0 || head > contentStart) return false;
  if (!isInListItemContext(view, contentStart, line.from)) return false;

  const prefix = line.text.slice(0, contentOffset);
  const insert = state.lineBreak + prefix;
  view.dispatch({
    changes: { from: contentStart, to: contentStart, insert },
    selection: EditorSelection.cursor(contentStart + insert.length),
    scrollIntoView: true,
    userEvent: "input",
  });
  return true;
}

// Wraps insertNewlineContinueMarkup to prevent spurious blank lines in tight lists.
// CodeMirror's nonTightList heuristic sometimes misclassifies long (visually
// wrapped) lines as loose, inserting "\n\n- " instead of "\n- ".
// This handler checks if the list was already loose before the keypress; if not
// and a blank line was inserted, it removes the extra newline.
function tightListEnter(view: EditorView): boolean {
  if (view.composing || view.dom.classList.contains(IME_COMPOSING_CLASS)) {
    return false;
  }

  // CodeMirror's list continuation command still produces invalid "-"/"- [ ]"
  // lines when Enter is pressed exactly at the content boundary of a non-empty
  // list item. Split that case manually so the current item becomes an empty
  // list item and the existing content moves to the next line.
  if (splitListItemAtContentStart(view)) {
    return true;
  }

  const state = view.state;
  const head = state.selection.main.head;
  const headLine = state.doc.lineAt(head);

  // Was the line immediately after the cursor already blank? (= existing loose list)
  const nextLineNum = headLine.number + 1;
  const wasLoose =
    nextLineNum <= state.doc.lines &&
    state.doc.line(nextLineNum).text.trim() === "";

  const result = continueMarkup(view);
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

  normalizeCursorToListContent(view);

  return true;
}

function wrapSelection(
  view: EditorView,
  open: string,
  close = open,
  opts: { userEvent?: string; skipEmpty?: boolean } = {}
): boolean {
  const changes = view.state.changeByRange((range) => {
    if (opts.skipEmpty && range.empty) return { range, changes: [] };
    const content = view.state.sliceDoc(range.from, range.to);
    return {
      changes: { from: range.from, to: range.to, insert: `${open}${content}${close}` },
      range: EditorSelection.range(range.from + open.length, range.to + open.length),
    };
  });
  view.dispatch(view.state.update(changes, {
    scrollIntoView: true,
    ...(opts.userEvent && { userEvent: opts.userEvent }),
  }));
  return true;
}

function toggleTaskAtCursor(view: EditorView): boolean {
  const sel = view.state.selection.main;
  const line = view.state.doc.lineAt(sel.head);
  const checkedTaskMatch = line.text.match(/^(\s*)([-*+])\s\[(x|X)\]\s(.*)$/);
  if (checkedTaskMatch) {
    const bracketStart = line.from + checkedTaskMatch[1].length + checkedTaskMatch[2].length + 2;
    view.dispatch({
      changes: { from: bracketStart, to: bracketStart + 1, insert: " " },
    });
    return true;
  }

  const uncheckedTaskMatch = line.text.match(/^(\s*)([-*+])\s\[ \]\s(.*)$/);
  if (uncheckedTaskMatch) {
    const bracketStart = line.from + uncheckedTaskMatch[1].length + uncheckedTaskMatch[2].length + 2;
    view.dispatch({
      changes: { from: bracketStart, to: bracketStart + 1, insert: "x" },
    });
    return true;
  }

  let replacement: string | null = null;
  const listItemMatch = line.text.match(/^(\s*)([-*+])\s(.*)$/);
  if (listItemMatch) {
    const [, indent, marker, content] = listItemMatch;
    replacement = `${indent}${marker} [ ] ${content}`;
  } else {
    const plainLineMatch = line.text.match(/^(\s*)(.+)$/);
    if (plainLineMatch) {
      const [, indent, content] = plainLineMatch;
      replacement = `${indent}- [ ] ${content}`;
    } else {
      const emptyLineMatch = line.text.match(/^(\s*)$/);
      if (!emptyLineMatch) return false;
      replacement = `${emptyLineMatch[1]}- [ ] `;
    }
  }

  const prefixDelta = replacement.length - line.text.length;
  const newCursor = Math.max(line.from, Math.min(sel.head + prefixDelta, line.from + replacement.length));
  view.dispatch({
    changes: { from: line.from, to: line.to, insert: replacement },
    selection: EditorSelection.cursor(newCursor),
    scrollIntoView: true,
  });
  return true;
}

// Shared setup for indent/dedent: resolves the list item context at the cursor.
// Returns null if the cursor is not on a list item or the selection is non-empty.
function resolveListItemContext(view: EditorView) {
  const state = view.state;
  const sel = state.selection.main;
  if (!sel.empty) return null;

  const line = state.doc.lineAt(sel.head);
  const match = LIST_ITEM_RE.exec(line.text);
  const contentOffset = listContentStartOffset(line.text);
  if (!match || contentOffset === null) return null;

  const unit = state.facet(indentUnit);
  const contentStart = line.from + contentOffset;
  const contentText = line.text.slice(contentStart - line.from);
  const cursorBeforeContent = sel.head < contentStart;

  return {
    line,
    match,
    unit,
    contentStart,
    contentText,
    cursorBeforeContent,
    sel,
  };
}

// Indents a list item in a single dispatch to avoid visual flicker.
// Using indentMore followed by a separate cursor dispatch caused the cursor to
// briefly appear before the list mark, then jump to after "- " one frame later.
// By inserting the indent unit and setting the final cursor position together,
// the two-step flicker is eliminated.
function indentListItem(view: EditorView): boolean {
  const ctx = resolveListItemContext(view);
  if (!ctx) return false;
  const { line, unit, contentStart, contentText, cursorBeforeContent, sel } = ctx;
  const keepAtContentStart = cursorBeforeContent || contentText.length === 0;
  const contentOffset = keepAtContentStart ? 0 : Math.max(0, sel.head - contentStart);
  const targetPos = contentStart + unit.length + contentOffset;

  view.dispatch({
    changes: { from: line.from, insert: unit },
    selection: EditorSelection.cursor(targetPos),
    scrollIntoView: true,
  });

  return true;
}

// Dedents a list item in a single dispatch to avoid visual flicker.
// Mirrors indentListItem — same two-step flicker fix for Shift+Tab.
function dedentListItem(view: EditorView): boolean {
  const ctx = resolveListItemContext(view);
  if (!ctx) return false;
  const { line, match, unit, contentStart, contentText, cursorBeforeContent, sel } = ctx;

  const currentIndent = match[1];
  if (currentIndent.length === 0) return false;

  const removeLen = Math.min(unit.length, currentIndent.length);
  const keepAtContentStart = cursorBeforeContent || contentText.length === 0;
  const contentOffset = keepAtContentStart ? 0 : Math.max(0, sel.head - contentStart);
  const targetPos = Math.max(line.from, contentStart - removeLen + contentOffset);

  view.dispatch({
    changes: { from: line.from, to: line.from + removeLen },
    selection: EditorSelection.cursor(targetPos),
    scrollIntoView: true,
  });

  return true;
}

function linkUrlAtPosition(view: EditorView, pos: number): string | null {
  const tree = syntaxTree(view.state);
  const node = tree.resolve(pos, -1);

  // Walk up the tree looking for a Link or URL node
  for (let n: typeof node | null = node; n; n = n.parent) {
    if (n.name === "Link") {
      // Find the URL child within the link
      let child = n.firstChild;
      while (child) {
        if (child.name === "URL") {
          return view.state.sliceDoc(child.from, child.to);
        }
        child = child.nextSibling;
      }
    }
    if (n.name === "URL") {
      return view.state.sliceDoc(n.from, n.to);
    }
  }
  return null;
}

export function openLink(url: string | null | undefined): boolean {
  if (!url) return false;
  postToSwift({ type: "openLink", url });
  return true;
}

export function openLinkAtPosition(view: EditorView, pos: number, fallbackUrl?: string | null): boolean {
  const url = linkUrlAtPosition(view, pos) ?? fallbackUrl;
  return openLink(url);
}

function openLinkAtCursor(view: EditorView): boolean {
  return openLinkAtPosition(view, view.state.selection.main.head);
}

export const tightListEnterKeymap: KeyBinding[] = [
  { any: (_view, event) => isImeAcceptEnter(event) },
  { key: "Enter", run: tightListEnter },
];

export const chiramiKeymap: KeyBinding[] = [
  { key: "Tab", run: indentListItem, shift: dedentListItem },
  { key: "Mod-b", run: (view) => wrapSelection(view, "**") },
  { key: "Mod-i", run: (view) => wrapSelection(view, "*") },
  { key: "Mod-l", run: toggleTaskAtCursor },
  { key: "Mod-Enter", run: openLinkAtCursor },
  { key: "Mod-[", run: foldCode },
  { key: "Mod-]", run: unfoldCode },
  { key: "Mod-Shift-[", run: foldAll },
  { key: "Mod-Shift-]", run: unfoldAll },
];

const SURROUND_PAIRS: Record<string, string> = {
  "*": "*",
  "`": "`",
  "_": "_",
  "~": "~",
  "(": ")",
  "[": "]",
  "{": "}",
  '"': '"',
  "'": "'",
};

export const surroundSelectionHandler = EditorView.inputHandler.of(
  (view, from, to, text) => {
    if (from === to) return false;
    if (text.length !== 1) return false;

    const close = SURROUND_PAIRS[text];
    if (!close) return false;

    return wrapSelection(view, text, close, { userEvent: "input.surroundSelection", skipEmpty: true });
  }
);
