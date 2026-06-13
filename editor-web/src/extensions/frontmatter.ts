import { syntaxTree } from "@codemirror/language";
import { EditorState, Range, StateField } from "@codemirror/state";
import { Decoration, DecorationSet, EditorView, WidgetType } from "@codemirror/view";
import { parse as parseYaml } from "yaml";
import {
  cursorLineFromState,
  cursorRevealField,
  transactionCursorRevealChanged,
  transactionHasWindowActiveEffect,
  windowActiveField,
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
  // Line-aligned range used for the block replacement decoration. blockTo is
  // the end of the closing "---" line, NOT including its trailing newline:
  // including the newline would make the body line's start coincide with the
  // replace range's end, which pushes a caret placed at the body line start
  // back to the block start (into the frontmatter).
  blockFrom: number;
  blockTo: number;
  // Start of the body line (just past the closing newline) — outside the
  // replace range. Used as the safe spot to park the caret (see caret guard).
  bodyStart: number;
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
    bodyStart: Math.min(state.doc.length, endLineObj.to + 1),
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

// Element holding the per-widget ResizeObserver so destroy() can disconnect it.
interface ChipsRoot extends HTMLElement {
  __chiramiFmObserver?: ResizeObserver;
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
    const container = document.createElement("div") as ChipsRoot;
    container.className = "cm-frontmatter-chips";

    const chips: HTMLElement[] = [];
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
      chips.push(chip);
    }

    // Overflow chip: how many fields are hidden because they don't fit on the
    // first row. Count is computed by measurement (relayout), not a fixed cap.
    const more = document.createElement("span");
    more.className = "cm-frontmatter-chip cm-frontmatter-chip-more";
    more.style.display = "none";
    container.appendChild(more);

    const total = this.entries.length;
    // Show as many chips as fit on the first row; collapse the rest into "+N".
    // Reading offsetTop forces layout but the chip count is small. Hiding chips
    // never widens the container (its width is bounded by the editor), so this
    // does not trigger a ResizeObserver feedback loop.
    const relayout = () => {
      for (const chip of chips) chip.style.display = "";
      more.style.display = "none";
      if (chips.length === 0) return;
      const rowTop = chips[0].offsetTop;
      let firstWrapped = chips.findIndex((c) => c.offsetTop > rowTop);
      if (firstWrapped === -1) return; // everything fits on one row

      let shownCount = firstWrapped;
      more.style.display = "";
      const apply = () => {
        chips.forEach((c, i) => (c.style.display = i < shownCount ? "" : "none"));
        const hidden = total - shownCount;
        more.textContent = `+${hidden}`;
        more.title = `${hidden} more — click to edit`;
      };
      apply();
      // Make room for the "+N" chip itself on the first row.
      while (shownCount > 0 && more.offsetTop > rowTop) {
        shownCount -= 1;
        apply();
      }
    };

    const observer = new ResizeObserver(() => relayout());
    observer.observe(container);
    container.__chiramiFmObserver = observer;

    // Clicking the chips switches to raw-edit mode by moving the cursor inside
    // the frontmatter (the next rebuild then drops the chips and shows the YAML).
    // preventDefault on mousedown stops CodeMirror's own pointer handler from
    // placing the cursor at the widget boundary (outside the block) and
    // overriding our dispatch; the actual selection is set on click (mouseup),
    // matching details.ts. A drag-selection is left alone.
    container.addEventListener("mousedown", (e) => e.preventDefault());
    container.addEventListener("click", (e) => {
      const selection = window.getSelection();
      if (selection && !selection.isCollapsed) return; // allow text selection
      e.preventDefault();
      e.stopPropagation();
      // userEvent "select" marks this as a deliberate interaction so the editor
      // "reveals" the cursor line (see cursorRevealField); without it the raw
      // YAML would not appear even though the cursor is inside the block.
      view.dispatch({ selection: { anchor: this.editFrom }, scrollIntoView: true, userEvent: "select" });
      view.focus();
    });

    return container;
  }

  destroy(dom: HTMLElement): void {
    (dom as ChipsRoot).__chiramiFmObserver?.disconnect();
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

// When a note is opened the cursor is often restored to offset 0, which is
// inside the leading frontmatter. While the cursor is "unrevealed" the chips
// are shown (correct), but CodeMirror still draws the caret at offset 0 — i.e.
// inside the block widget — producing a giant, full-height blinking caret.
// Nudge the caret just past the frontmatter in that case. This runs only while
// unrevealed, so it never fights a deliberate cursor move into the block (which
// reveals and shows raw YAML), and it does not reveal the body line.
const frontmatterCaretGuard = EditorView.updateListener.of((update) => {
  const { state } = update;
  if (state.field(cursorRevealField, false)) return; // user is interacting → leave caret
  if (!(state.field(windowActiveField, false) ?? true)) return; // hidden → caret not drawn
  const sel = state.selection.main;
  if (!sel.empty) return;
  const range = findFrontmatter(state);
  if (!range) return;
  if (sel.head < range.blockFrom || sel.head > range.blockTo) return; // already outside
  if (range.bodyStart === sel.head) return;
  update.view.dispatch({ selection: { anchor: range.bodyStart } });
});

export const frontmatterExtension = [frontmatterDecorations, frontmatterCaretGuard];
