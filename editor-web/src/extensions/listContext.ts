import { syntaxTree } from "@codemirror/language";
import { markdownLanguage } from "@codemirror/lang-markdown";
import { EditorState, Line } from "@codemirror/state";
import type { SyntaxNode } from "@lezer/common";

/** List item that starts on a given line, resolved from the Markdown syntax tree. */
export interface ListLine {
  line: Line;
  item: SyntaxNode;
  /** Leading whitespace of the line (the item's indentation). */
  indent: string;
  /** Marker text without trailing space, e.g. "-" or "3." */
  marker: string;
  /** Absolute position where the item's text starts (after marker and task box). */
  contentStart: number;
  ordered: boolean;
}

/** Returns the list item whose first line is `line`, or null. */
export function listLineAt(state: EditorState, line: Line): ListLine | null {
  const indentLen = line.text.length - line.text.trimStart().length;
  if (indentLen === line.length) return null;
  const tree = syntaxTree(state);
  let node: SyntaxNode | null = tree.resolveInner(line.from + indentLen, 1);
  for (; node; node = node.parent) {
    if (node.name === "ListItem") break;
  }
  if (!node || state.doc.lineAt(node.from).number !== line.number) return null;
  const mark = node.getChild("ListMark");
  if (!mark || mark.from !== line.from + indentLen) return null;

  let contentStart = mark.to;
  const task = node.getChild("Task");
  const taskMarker = task?.getChild("TaskMarker");
  if (taskMarker && state.doc.lineAt(taskMarker.from).number === line.number) {
    contentStart = taskMarker.to;
  }
  // Skip the separating whitespace (on this line only).
  while (contentStart < line.to && (line.text[contentStart - line.from] === " " || line.text[contentStart - line.from] === "\t")) {
    contentStart++;
  }
  return {
    line,
    item: node,
    indent: line.text.slice(0, indentLen),
    marker: state.sliceDoc(mark.from, mark.to),
    contentStart,
    ordered: node.parent?.name === "OrderedList",
  };
}

/** Visual width of leading whitespace with the given tab size. */
export function indentWidth(indent: string, tabSize: number): number {
  let w = 0;
  for (const ch of indent) {
    if (ch === "\t") w += tabSize - (w % tabSize);
    else if (ch === " ") w += 1;
    else break;
  }
  return w;
}

export function leadingWhitespace(text: string): string {
  return text.slice(0, text.length - text.trimStart().length);
}

/**
 * Last line number of the subtree rooted at the list item on `lineNumber`:
 * the item itself plus every following line indented deeper than it
 * (blank lines are included only when deeper lines follow them).
 */
export function subtreeEnd(state: EditorState, lineNumber: number): number {
  const tabSize = state.tabSize;
  const doc = state.doc;
  const base = indentWidth(leadingWhitespace(doc.line(lineNumber).text), tabSize);
  let end = lineNumber;
  for (let n = lineNumber + 1; n <= doc.lines; n++) {
    const text = doc.line(n).text;
    if (text.trim() === "") continue;
    if (indentWidth(leadingWhitespace(text), tabSize) <= base) break;
    end = n;
  }
  return end;
}

/** A pasted line of a pure Markdown list: nesting depth and text from the marker on. */
export interface PastedListLine {
  depth: number;
  text: string;
}

/**
 * Parses `text` as Markdown and returns its lines with list depth when every
 * non-blank line starts a list item; otherwise null.
 */
export function parsePastedList(text: string): PastedListLine[] | null {
  const lines = text.replace(/\n+$/, "").split("\n");
  if (lines.length === 0) return null;
  const tree = markdownLanguage.parser.parse(text);
  const out: PastedListLine[] = [];
  let pos = 0;
  for (const raw of lines) {
    const lineStart = pos;
    pos += raw.length + 1;
    if (raw.trim() === "") continue;
    const first = lineStart + (raw.length - raw.trimStart().length);
    let node: SyntaxNode | null = tree.resolveInner(first, 1);
    let mark: SyntaxNode | null = null;
    for (; node; node = node.parent) {
      if (node.name === "ListMark" && node.from === first) mark = node;
      if (node.name === "ListItem") break;
    }
    if (!node || !mark) return null;
    let depth = -1;
    for (let p: SyntaxNode | null = node; p; p = p.parent) {
      if (p.name === "ListItem") depth++;
    }
    out.push({ depth, text: raw.trimStart() });
  }
  return out.length > 0 ? out : null;
}
