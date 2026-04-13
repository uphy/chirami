import { syntaxTree } from "@codemirror/language";
import { Prec, Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
  WidgetType,
  keymap,
} from "@codemirror/view";
import { createElement } from "react";
import { createRoot, Root } from "react-dom/client";
import { TldrawImage, TLEditorSnapshot, TLStoreSnapshot } from "tldraw";
import { openTldrawOverlay } from "../tldraw-overlay";
import { cursorLineNumber, nodeContainsCursorLine, shouldRebuild, tryParseJSON } from "./utils";

// Returns true if the snapshot JSON has no shape records (empty canvas).
function isEmptyTldrawSnapshot(json: string): boolean {
  const parsed = tryParseJSON<TLEditorSnapshot | TLStoreSnapshot>(json);
  if (!parsed) return true;
  const store =
    "document" in parsed
      ? (parsed.document as { store?: Record<string, unknown> }).store
      : (parsed as { store?: Record<string, unknown> }).store;
  if (!store) return true;
  return !Object.keys(store).some((key) => key.startsWith("shape:"));
}

const tldrawHideMark = Decoration.mark({ class: "cm-tldraw-raw" });

interface TldrawWidgetInfo {
  json: string;
  codeFrom: number;
  codeTo: number;
}

interface TldrawBlockRef {
  json: string;
  codeFrom: number;
  codeTo: number;
  blockFrom: number;
  blockTo: number;
}

class TldrawPreviewWidget extends WidgetType {
  private root: Root | null = null;
  private destroyed = false;

  constructor(private info: TldrawWidgetInfo) {
    super();
  }

  eq(other: TldrawPreviewWidget): boolean {
    return other.info.json === this.info.json && other.info.codeFrom === this.info.codeFrom;
  }

  toDOM(view: EditorView): HTMLElement {
    this.destroyed = false;

    const wrap = document.createElement("div");
    wrap.className = "cm-tldraw-container";

    if (!this.info.json.trim() || isEmptyTldrawSnapshot(this.info.json)) {
      // Empty block or empty canvas (no shapes): show placeholder
      const placeholder = document.createElement("div");
      placeholder.className = "cm-tldraw-placeholder";
      placeholder.textContent = "Click to add a diagram";
      wrap.appendChild(placeholder);
      wrap.addEventListener("click", () => this.openOverlay(view));
    } else {
      // Render SVG preview
      this.renderPreview(wrap);
    }

    // Edit button (shown on hover via CSS)
    const editBtn = document.createElement("button");
    editBtn.className = "cm-tldraw-edit-btn";
    editBtn.textContent = "Edit";
    editBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      this.openOverlay(view);
    });
    wrap.appendChild(editBtn);

    wrap.addEventListener("mouseenter", () => wrap.classList.add("cm-tldraw-hover"));
    wrap.addEventListener("mouseleave", () => wrap.classList.remove("cm-tldraw-hover"));

    return wrap;
  }

  private renderPreview(container: HTMLElement): void {
    if (this.destroyed) return;

    const snapshot = tryParseJSON<TLEditorSnapshot | TLStoreSnapshot>(this.info.json);
    if (!snapshot) {
      this.insertBeforeEditButton(container, this.makeErrorEl("Invalid JSON"));
      return;
    }

    const previewEl = document.createElement("div");
    previewEl.className = "cm-tldraw-preview-inner";
    this.insertBeforeEditButton(container, previewEl);

    this.root = createRoot(previewEl);
    this.root.render(createElement(TldrawImage, { snapshot, background: true, darkMode: false }));
  }

  private makeErrorEl(msg: string): HTMLElement {
    const el = document.createElement("div");
    el.className = "cm-tldraw-error";
    el.textContent = msg;
    return el;
  }

  private insertBeforeEditButton(container: HTMLElement, el: HTMLElement): void {
    container.insertBefore(el, container.lastElementChild);
  }

  private openOverlay(view: EditorView): void {
    openTldrawOverlay(this.info.json, (newSnapshot) => {
      this.updateCodeBlock(view, newSnapshot);
    });
  }

  private updateCodeBlock(view: EditorView, newSnapshot: string): void {
    if (newSnapshot === this.info.json) return;
    view.dispatch({
      changes: { from: this.info.codeFrom, to: this.info.codeTo, insert: newSnapshot + "\n" },
    });
  }

  destroy(_dom: HTMLElement): void {
    this.destroyed = true;
    this.root?.unmount();
    this.root = null;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

class TldrawPlugin {
  decorations: DecorationSet;
  blocks: TldrawBlockRef[] = [];

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate): void {
    if (shouldRebuild(update)) {
      this.decorations = this.build(update.view);
    }
  }

  private build(view: EditorView): DecorationSet {
    const cursorLine = cursorLineNumber(view);
    const decorations: Range<Decoration>[] = [];
    this.blocks = [];

    for (const { from, to } of view.visibleRanges) {
      syntaxTree(view.state).iterate({
        from,
        to,
        enter: (node) => {
          if (node.name !== "FencedCode") return;

          const codeInfoNode = node.node.getChild("CodeInfo");
          if (!codeInfoNode) return false;
          const lang = view.state
            .sliceDoc(codeInfoNode.from, codeInfoNode.to)
            .trim()
            .toLowerCase();
          if (lang !== "tldraw") return false;

          const codeTextNode = node.node.getChild("CodeText");
          const json = codeTextNode
            ? view.state.sliceDoc(codeTextNode.from, codeTextNode.to).trim()
            : "";

          // codeFrom/codeTo: the range to replace when saving
          let codeFrom: number;
          let codeTo: number;
          if (codeTextNode) {
            codeFrom = codeTextNode.from;
            codeTo = codeTextNode.to;
          } else {
            // No CodeText node (empty block): insert after the opening fence line
            const openFenceLine = view.state.doc.lineAt(node.from);
            codeFrom = openFenceLine.to + 1;
            codeTo = codeFrom;
          }

          // Track all tldraw blocks for keymap access (regardless of cursor position)
          this.blocks.push({ json, codeFrom, codeTo, blockFrom: node.from, blockTo: node.to });

          if (nodeContainsCursorLine(view, node.from, node.to, cursorLine)) return false;

          const startLine = view.state.doc.lineAt(node.from);
          const endLine = view.state.doc.lineAt(node.to);

          const info: TldrawWidgetInfo = { json, codeFrom, codeTo };

          decorations.push(
            Decoration.widget({
              widget: new TldrawPreviewWidget(info),
              side: -1,
            }).range(startLine.from)
          );
          decorations.push(tldrawHideMark.range(startLine.from, endLine.to));

          return false;
        },
      });
    }

    return decorations.length > 0 ? Decoration.set(decorations, true) : Decoration.none;
  }
}

const tldrawPlugin = ViewPlugin.fromClass(TldrawPlugin, {
  decorations: (v) => v.decorations,
});

const tldrawKeymap = keymap.of([
  {
    key: "Mod-Enter",
    run(view: EditorView): boolean {
      const plugin = view.plugin(tldrawPlugin);
      if (!plugin) return false;

      const cursor = view.state.selection.main.head;
      const block = plugin.blocks.find((b) => b.blockFrom <= cursor && cursor <= b.blockTo);
      if (!block) return false;

      openTldrawOverlay(block.json, (newSnapshot) => {
        if (newSnapshot === block.json) return;
        view.dispatch({
          changes: { from: block.codeFrom, to: block.codeTo, insert: newSnapshot + "\n" },
        });
      });
      return true;
    },
  },
]);

export const tldrawExtension = [tldrawPlugin, Prec.high(tldrawKeymap)];
