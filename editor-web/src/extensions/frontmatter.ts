import { syntaxTree } from "@codemirror/language";
import { EditorState, Range, StateField } from "@codemirror/state";
import { Decoration, DecorationSet, EditorView, WidgetType } from "@codemirror/view";
import { parse as parseYaml } from "yaml";
import {
  cursorLineFromState,
  transactionCursorRevealChanged,
  transactionHasWindowActiveEffect,
} from "./utils";
import { postToSwift } from "../bridge";

// Frontmatter is the leading `---` … `---` YAML block. The editor language is
// wrapped with yamlFrontmatter (see editor.ts), so a single "Frontmatter" node
// appears at the document start. Two display states:
//   - chips (cursor outside): a compact, read-only row of key/value chips
//     shown above the body so the frontmatter is always glanceable
//   - raw (cursor inside): the underlying YAML, edited directly
// The chips view never rewrites the document — it is display-only, keeping the
// file byte-for-byte intact (Obsidian non-destructive compatibility).

interface FrontmatterRange {
  // Line-aligned range used for the block replacement decoration.
  blockFrom: number;
  blockTo: number;
  startLine: number;
  endLine: number;
  // YAML body between the two `---` dash lines.
  contentFrom: number;
  contentTo: number;
}

// Locate the leading frontmatter via the syntax tree. Returns null when the
// language is not wrapped with yamlFrontmatter or the block is absent/unclosed.
function findFrontmatter(state: EditorState): FrontmatterRange | null {
  const tree = syntaxTree(state);
  const top = tree.topNode.firstChild;
  if (!top || top.name !== "Frontmatter") return null;

  // node.to points at the body start (just past the closing "---\n"), so the
  // closing dash line is the line containing node.to - 1.
  const startLineObj = state.doc.lineAt(top.from);
  const endLineObj = state.doc.lineAt(Math.max(top.from, top.to - 1));

  const openDash = top.firstChild;
  const closeDash = top.lastChild;
  const contentFrom = openDash ? openDash.to : startLineObj.to;
  const contentTo = closeDash ? closeDash.from : endLineObj.from;

  return {
    blockFrom: startLineObj.from,
    blockTo: endLineObj.to,
    startLine: startLineObj.number,
    endLine: endLineObj.number,
    contentFrom,
    contentTo: Math.max(contentFrom, contentTo),
  };
}

// Render a top-level YAML value compactly. Arrays join with a middle dot;
// nested objects are summarised by their key names (not deep-expanded); empty
// or null values show a dash. Long scalars are clipped via CSS with the full
// text in a title attribute by the caller.
function formatValue(value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  if (Array.isArray(value)) {
    if (value.length === 0) return "—";
    return value.map((item) => formatScalar(item)).join(" · ");
  }
  if (typeof value === "object") {
    const keys = Object.keys(value as Record<string, unknown>);
    if (keys.length === 0) return "{ }";
    const shown = keys.slice(0, 3).join(", ");
    return `{ ${shown}${keys.length > 3 ? " …" : ""} }`;
  }
  return formatScalar(value);
}

function formatScalar(value: unknown): string {
  if (value === null || value === undefined) return "—";
  if (typeof value === "object") {
    // Array item that is itself a map/array: keep it short.
    return Array.isArray(value) ? `[${value.length}]` : "{…}";
  }
  return String(value);
}

interface FrontmatterEntry {
  key: string;
  display: string;
  raw: string;
}

class FrontmatterChipsWidget extends WidgetType {
  constructor(
    private readonly entries: FrontmatterEntry[],
    private readonly editFrom: number,
    private readonly signature: string,
  ) {
    super();
  }

  eq(other: FrontmatterChipsWidget): boolean {
    return other.signature === this.signature && other.editFrom === this.editFrom;
  }

  toDOM(view: EditorView): HTMLElement {
    const container = document.createElement("div");
    container.className = "cm-frontmatter-chips";

    for (const entry of this.entries) {
      const chip = document.createElement("span");
      chip.className = "cm-frontmatter-chip";

      if (entry.key) {
        const key = document.createElement("span");
        key.className = "cm-frontmatter-chip-key";
        key.textContent = entry.key;
        chip.appendChild(key);
      }

      const value = document.createElement("span");
      value.className = "cm-frontmatter-chip-value";
      value.textContent = entry.display;
      if (entry.raw !== entry.display) value.title = entry.raw;
      chip.appendChild(value);

      container.appendChild(chip);
    }

    // Clicking the chips (but not while selecting text) places the cursor
    // inside the frontmatter so the next rebuild reveals the raw YAML to edit.
    container.addEventListener("mousedown", (e) => {
      const selection = window.getSelection();
      if (selection && !selection.isCollapsed) return; // allow text selection
      e.preventDefault();
      view.dispatch({ selection: { anchor: this.editFrom }, scrollIntoView: true });
      view.focus();
    });

    return container;
  }

  ignoreEvent(): boolean {
    return false;
  }
}

function buildFrontmatterDecorations(state: EditorState): DecorationSet {
  try {
    return _buildFrontmatterDecorations(state);
  } catch (e) {
    postToSwift({ type: "log", level: "error", message: `FrontmatterPlugin build error: ${e}` });
    return Decoration.none;
  }
}

function _buildFrontmatterDecorations(state: EditorState): DecorationSet {
  const range = findFrontmatter(state);
  if (!range) return Decoration.none;

  // Raw mode: cursor sits on any frontmatter line → show the underlying YAML.
  const cursorLine = cursorLineFromState(state);
  if (cursorLine >= range.startLine && cursorLine <= range.endLine) {
    return Decoration.none;
  }

  const entries = parseFrontmatterEntries(state, range);
  if (!entries || entries.length === 0) {
    // Invalid YAML mid-edit or empty frontmatter: fall back to raw rather than
    // an empty chip row.
    return Decoration.none;
  }

  // First content line start, where the cursor lands when the user clicks to edit.
  const editFrom = state.doc.lineAt(range.contentFrom).from;
  const signature = entries.map((e) => `${e.key}=${e.display}`).join(" ");
  return Decoration.set([
    Decoration.replace({
      widget: new FrontmatterChipsWidget(entries, editFrom, signature),
      block: true,
    }).range(range.blockFrom, range.blockTo),
  ]);
}

// Parse the YAML body into top-level entries. Returns null on parse failure.
function parseFrontmatterEntries(state: EditorState, range: FrontmatterRange): FrontmatterEntry[] | null {
  const text = state.sliceDoc(range.contentFrom, range.contentTo);
  let parsed: unknown;
  try {
    parsed = parseYaml(text);
  } catch {
    return null;
  }
  if (parsed === null || parsed === undefined) return [];
  if (typeof parsed !== "object" || Array.isArray(parsed)) {
    // Non-mapping frontmatter (rare): show the whole thing as a single value.
    const display = formatValue(parsed);
    return [{ key: "", display, raw: display }];
  }
  return Object.entries(parsed as Record<string, unknown>).map(([key, value]) => {
    const display = formatValue(value);
    return { key, display, raw: typeof value === "string" ? value : display };
  });
}

const frontmatterDecorations = StateField.define<DecorationSet>({
  create: (state) => buildFrontmatterDecorations(state),
  update: (deco, tr) => {
    if (
      transactionHasWindowActiveEffect(tr) ||
      transactionCursorRevealChanged(tr) ||
      tr.docChanged ||
      tr.isUserEvent("external") ||
      tr.startState.selection.main.head !== tr.state.selection.main.head
    ) {
      return buildFrontmatterDecorations(tr.state);
    }
    return deco.map(tr.changes);
  },
  provide: (field) => EditorView.decorations.from(field),
});

export const frontmatterExtension = [frontmatterDecorations];
