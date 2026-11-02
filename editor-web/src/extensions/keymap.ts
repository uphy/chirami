import { syntaxTree, foldCode, unfoldCode, foldAll, unfoldAll } from "@codemirror/language";
import { EditorSelection, EditorState, Line } from "@codemirror/state";
import { EditorView, KeyBinding } from "@codemirror/view";
import { insertNewlineContinueMarkupCommand } from "@codemirror/lang-markdown";
import { postToSwift } from "../bridge";
import { wikiLinkTargetAtPosition } from "./wikilink";
import {
  cursorCjkWordLeft,
  cursorCjkWordRight,
  cursorLineUpIntoBlock,
  cursorSmartLineStart,
  dedentListItem,
  exitEmptyQuote,
  indentListItem,
  killLine,
  lineContentStart,
  moveListItemDown,
  moveListItemUp,
  listSoftBreak,
  nextTableCell,
  previousTableCell,
  selectCjkWordLeft,
  selectCjkWordRight,
  selectLineUpIntoBlock,
  selectSmartLineStart,
} from "./editingCommands";

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
  const start = syntaxTree(view.state).resolveInner(pos, -1);
  for (let node: typeof start | null = start; node; node = node.parent) {
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

  // Enter on an empty "> " line leaves the quote (CodeMirror keeps adding ">").
  if (exitEmptyQuote(view)) {
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
    // Word selections made with Option-Right include the leading space, and
    // "** bold**" is not emphasis in CommonMark: keep edge whitespace outside.
    const { from, to } = trimRange(view.state, range.from, range.to);
    const content = view.state.sliceDoc(from, to);
    return {
      changes: { from, to, insert: `${open}${content}${close}` },
      range: EditorSelection.range(from + open.length, to + open.length),
    };
  });
  view.dispatch(view.state.update(changes, {
    scrollIntoView: true,
    ...(opts.userEvent && { userEvent: opts.userEvent }),
  }));
  return true;
}

function trimRange(state: EditorState, from: number, to: number): { from: number; to: number } {
  const text = state.sliceDoc(from, to);
  if (text.trim() === "") return { from, to };
  const lead = text.length - text.trimStart().length;
  const trail = text.length - text.trimEnd().length;
  return { from: from + lead, to: to - trail };
}

/**
 * Cmd-B / Cmd-I: wrap the selection, or unwrap it when it is already wrapped
 * (markers just outside the selection, or the selection includes them).
 */
function toggleEmphasis(view: EditorView, marker: string): boolean {
  const state = view.state;
  const sel = state.selection.main;
  if (sel.empty) return wrapSelection(view, marker);
  const { from, to } = trimRange(state, sel.from, sel.to);
  const n = marker.length;
  const isMarker = (a: number, b: number) =>
    state.sliceDoc(a, b) === marker &&
    // "*" must not be half of "**".
    (n !== 1 || (state.sliceDoc(a - 1, a) !== "*" && state.sliceDoc(b, b + 1) !== "*"));

  if (from - n >= 0 && isMarker(from - n, from) && isMarker(to, to + n)) {
    view.dispatch({
      changes: [{ from: from - n, to: from }, { from: to, to: to + n }],
      selection: EditorSelection.range(from - n, to - n),
      scrollIntoView: true,
    });
    return true;
  }
  if (to - from > 2 * n && isMarker(from, from + n) && isMarker(to - n, to)) {
    view.dispatch({
      changes: [{ from, to: from + n }, { from: to - n, to }],
      selection: EditorSelection.range(from, to - 2 * n),
      scrollIntoView: true,
    });
    return true;
  }
  return wrapSelection(view, marker);
}

function toggleTaskAtCursor(view: EditorView): boolean {
  const sel = view.state.selection.main;
  const fullLine = view.state.doc.lineAt(sel.head);
  // Headings stay headings: "- [ ] ## Title" is neither a task nor a heading.
  if (headingOnLine(view.state, fullLine)) return true;
  // Inside a blockquote the task goes after the "> " markers.
  const prefixLen = quotePrefixLength(view.state, fullLine);
  const line = { from: fullLine.from + prefixLen, to: fullLine.to, text: fullLine.text.slice(prefixLen) };
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

  let replacement: string;
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
  const newCursor = Math.max(line.from, Math.min(Math.max(sel.head, line.from) + prefixDelta, line.from + replacement.length));
  view.dispatch({
    changes: { from: line.from, to: line.to, insert: replacement },
    selection: EditorSelection.cursor(newCursor),
    scrollIntoView: true,
  });
  return true;
}

function headingOnLine(state: EditorState, line: Line): boolean {
  let found = false;
  syntaxTree(state).iterate({
    from: line.from,
    to: line.to,
    enter: (node) => {
      if (node.name.startsWith("ATXHeading") && node.from >= line.from) found = true;
    },
  });
  return found;
}

/** Length of the "> " quote markup at the start of the line (0 outside quotes). */
function quotePrefixLength(state: EditorState, line: Line): number {
  const content = lineContentStart(state, line);
  let hasQuote = false;
  syntaxTree(state).iterate({
    from: line.from,
    to: Math.max(line.from, content),
    enter: (node) => {
      if (node.name === "QuoteMark" && node.from >= line.from) hasQuote = true;
    },
  });
  if (!hasQuote) return 0;
  // Stop before any list marker so "> - item" keeps "- " for the task logic.
  let end = line.from;
  syntaxTree(state).iterate({
    from: line.from,
    to: line.to,
    enter: (node) => {
      if (node.name === "QuoteMark" && node.from >= line.from) end = Math.max(end, node.to);
    },
  });
  while (end < line.to && line.text[end - line.from] === " ") end++;
  return end - line.from;
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
  // GFM autolinks like "www.example.com" carry no scheme; Swift's URL(string:)
  // cannot open them, so default to https.
  const normalized = /^www\./i.test(url) ? `https://${url}` : url;
  postToSwift({ type: "openLink", url: normalized });
  return true;
}

export function openWikiLink(target: string | null | undefined): boolean {
  if (!target) return false;
  postToSwift({ type: "openWikiLink", target });
  return true;
}

export function openLinkAtPosition(view: EditorView, pos: number, fallbackUrl?: string | null): boolean {
  // Wiki links resolve to local files on the Swift side; check them before
  // falling back to standard URL links.
  const wiki = wikiLinkTargetAtPosition(view, pos);
  if (wiki) return openWikiLink(wiki);
  const url = linkUrlAtPosition(view, pos) ?? fallbackUrl;
  return openLink(url);
}

function openLinkAtCursor(view: EditorView): boolean {
  return openLinkAtPosition(view, view.state.selection.main.head);
}

export const tightListEnterKeymap: KeyBinding[] = [
  { any: (_view, event) => isImeAcceptEnter(event) },
  { key: "Enter", run: tightListEnter },
  { key: "Shift-Enter", run: listSoftBreak },
];

export const chiramiKeymap: KeyBinding[] = [
  { key: "Tab", run: nextTableCell, shift: previousTableCell },
  { key: "Tab", run: indentListItem, shift: dedentListItem },
  // Emacs-style keys that reach the editor raw (not remapped by Karabiner).
  { mac: "Ctrl-a", run: cursorSmartLineStart, shift: selectSmartLineStart },
  { mac: "Ctrl-k", run: killLine },
  { key: "Alt-ArrowLeft", run: cursorCjkWordLeft, shift: selectCjkWordLeft },
  { key: "Alt-ArrowRight", run: cursorCjkWordRight, shift: selectCjkWordRight },
  { key: "ArrowUp", run: cursorLineUpIntoBlock, shift: selectLineUpIntoBlock },
  { key: "Alt-ArrowUp", run: moveListItemUp },
  { key: "Alt-ArrowDown", run: moveListItemDown },
  { mac: "Ctrl-p", run: cursorLineUpIntoBlock, shift: selectLineUpIntoBlock },
  { key: "Mod-b", run: (view) => toggleEmphasis(view, "**") },
  { key: "Mod-i", run: (view) => toggleEmphasis(view, "*") },
  { key: "Mod-l", run: toggleTaskAtCursor },
  { key: "Mod-Enter", run: openLinkAtCursor },
  { key: "Mod-[", run: foldCode },
  { key: "Mod-]", run: unfoldCode },
  { key: "Mod-Shift-[", run: foldAll },
  { key: "Mod-Shift-]", run: unfoldAll },
];

// Only Markdown emphasis markers wrap a selection. Brackets and quotes replace
// it like normal typing: selecting a word to retype it as "(…)" is common, and
// wrapping there surprised users.
const SURROUND_PAIRS: Record<string, string> = {
  "*": "*",
  "`": "`",
  "_": "_",
  "~": "~",
  "=": "=",  // type = twice over a selection to wrap as ==highlight==
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
