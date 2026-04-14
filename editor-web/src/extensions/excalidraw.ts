import { syntaxTree } from "@codemirror/language";
import { Prec, Range, RangeSet, RangeSetBuilder } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
  WidgetType,
  keymap,
} from "@codemirror/view";
import { exportToSvg } from "@excalidraw/excalidraw";
import { openExcalidrawOverlay } from "../excalidraw-overlay";
import { isEmptyExcalidrawScene, parseExcalidrawScene } from "./excalidrawShared";
import { shouldRebuild } from "./utils";

const excalidrawHideMark = Decoration.mark({ class: "cm-excalidraw-raw" });

interface ExcalidrawBlockRef {
  json: string;
  codeFrom: number;
  codeTo: number;
  blockFrom: number;
  blockTo: number;
}

class ExcalidrawPreviewWidget extends WidgetType {
  private destroyed = false;

  constructor(
    private readonly json: string,
    private codeFrom: number,
    private codeTo: number,
  ) {
    super();
  }

  eq(other: ExcalidrawPreviewWidget): boolean {
    return other.json === this.json;
  }

  get estimatedHeight(): number {
    return 180;
  }

  toDOM(view: EditorView): HTMLElement {
    this.destroyed = false;

    const wrap = document.createElement("div");
    wrap.className = "cm-excalidraw-container";

    if (!this.json.trim() || isEmptyExcalidrawScene(this.json)) {
      const placeholder = document.createElement("div");
      placeholder.className = "cm-excalidraw-placeholder";
      placeholder.textContent = "Click to add a diagram";
      wrap.appendChild(placeholder);
      wrap.addEventListener("click", () => this.openOverlay(view));
    } else {
      this.renderPreview(wrap, view);
    }

    const editBtn = document.createElement("button");
    editBtn.className = "cm-excalidraw-edit-btn";
    editBtn.textContent = "Edit";
    editBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      this.openOverlay(view);
    });
    wrap.appendChild(editBtn);

    wrap.addEventListener("mouseenter", () => wrap.classList.add("cm-excalidraw-hover"));
    wrap.addEventListener("mouseleave", () => wrap.classList.remove("cm-excalidraw-hover"));

    return wrap;
  }

  private async renderPreview(container: HTMLElement, view: EditorView): Promise<void> {
    const scene = parseExcalidrawScene(this.json);
    if (!scene) {
      container.insertBefore(this.makeErrorEl("Invalid JSON"), container.lastElementChild);
      return;
    }

    const previewEl = document.createElement("div");
    previewEl.className = "cm-excalidraw-preview-inner";
    container.insertBefore(previewEl, container.lastElementChild);

    try {
      const svg = await exportToSvg({
        elements: scene.elements,
        appState: {
          ...(scene.appState ?? {}),
          exportBackground: false,
          viewBackgroundColor: "transparent",
        },
        files: scene.files ?? {},
        exportPadding: 0,
        renderEmbeddables: true,
      });

      if (this.destroyed || !previewEl.isConnected) return;
      const serialized = new XMLSerializer().serializeToString(svg);
      const img = document.createElement("img");
      img.alt = "Excalidraw diagram preview";
      img.decoding = "async";
      img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(serialized)}`;
      previewEl.replaceChildren(img);
      view.requestMeasure();
    } catch (err) {
      if (this.destroyed || !previewEl.isConnected) return;
      previewEl.replaceChildren(this.makeErrorEl(err instanceof Error ? err.message : "Failed to render preview"));
      view.requestMeasure();
    }
  }

  private makeErrorEl(msg: string): HTMLElement {
    const el = document.createElement("div");
    el.className = "cm-excalidraw-error";
    el.textContent = msg;
    return el;
  }

  private openOverlay(view: EditorView): void {
    openExcalidrawOverlay(this.json, (newSnapshot) => {
      this.updateCodeBlock(view, newSnapshot);
    });
  }

  private updateCodeBlock(view: EditorView, newSnapshot: string): void {
    if (newSnapshot === this.json) return;
    view.dispatch({
      changes: { from: this.codeFrom, to: this.codeTo, insert: newSnapshot + "\n" },
    });
  }

  destroy(_dom: HTMLElement): void {
    this.destroyed = true;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

class ExcalidrawPlugin {
  decorations: DecorationSet;
  blocks: ExcalidrawBlockRef[] = [];
  atomicRangeSet: RangeSet<Decoration> = Decoration.none;

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate): void {
    if (shouldRebuild(update)) {
      this.decorations = this.build(update.view);
    }
  }

  private build(view: EditorView): DecorationSet {
    const decorations: Range<Decoration>[] = [];
    const atomicBuilder = new RangeSetBuilder<Decoration>();
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
          if (lang !== "excalidraw") return false;

          const codeTextNode = node.node.getChild("CodeText");
          const json = codeTextNode
            ? view.state.sliceDoc(codeTextNode.from, codeTextNode.to).trim()
            : "";

          let codeFrom: number;
          let codeTo: number;
          if (codeTextNode) {
            codeFrom = codeTextNode.from;
            codeTo = codeTextNode.to;
          } else {
            const openFenceLine = view.state.doc.lineAt(node.from);
            codeFrom = openFenceLine.to + 1;
            codeTo = codeFrom;
          }

          this.blocks.push({ json, codeFrom, codeTo, blockFrom: node.from, blockTo: node.to });
          atomicBuilder.add(node.from, node.to, excalidrawHideMark);

          const startLine = view.state.doc.lineAt(node.from);
          const endLine = view.state.doc.lineAt(node.to);

          decorations.push(
            Decoration.widget({
              widget: new ExcalidrawPreviewWidget(json, codeFrom, codeTo),
              side: -1,
            }).range(startLine.from)
          );
          decorations.push(excalidrawHideMark.range(startLine.from, endLine.to));

          return false;
        },
      });
    }

    this.atomicRangeSet = this.blocks.length > 0 ? atomicBuilder.finish() : Decoration.none;
    return decorations.length > 0 ? Decoration.set(decorations, true) : Decoration.none;
  }
}

const excalidrawPlugin = ViewPlugin.fromClass(ExcalidrawPlugin, {
  decorations: (v) => v.decorations,
});

const excalidrawAtomicRanges = EditorView.atomicRanges.of((view) => {
  return view.plugin(excalidrawPlugin)?.atomicRangeSet ?? Decoration.none;
});

const excalidrawKeymap = keymap.of([
  {
    key: "Mod-Enter",
    run(view: EditorView): boolean {
      const plugin = view.plugin(excalidrawPlugin);
      if (!plugin) return false;

      const cursor = view.state.selection.main.head;
      const block = plugin.blocks.find((b) => b.blockFrom <= cursor && cursor <= b.blockTo);
      if (!block) return false;

      openExcalidrawOverlay(block.json, (newSnapshot) => {
        if (!newSnapshot) return;
        view.dispatch({
          changes: { from: block.codeFrom, to: block.codeTo, insert: newSnapshot + "\n" },
        });
      });
      return true;
    },
  },
]);

export const excalidrawExtension = [excalidrawPlugin, excalidrawAtomicRanges, Prec.high(excalidrawKeymap)];
