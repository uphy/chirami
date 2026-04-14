import { syntaxTree } from "@codemirror/language";
import { Prec, Range, StateField } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorState,
  EditorView,
  WidgetType,
  keymap,
} from "@codemirror/view";
import { exportToSvg } from "@excalidraw/excalidraw";
import { openExcalidrawOverlay } from "../excalidraw-overlay";
import { isEmptyExcalidrawScene, parseExcalidrawScene } from "./excalidrawShared";
import { CodeBlockSizeOptions, applySizeOptions, cursorLineFromState, makeDecorationField, parseCodeBlockInfo, sizeOptionsEq } from "./utils";

interface ExcalidrawBlockRef {
  json: string;
  codeFrom: number;
  codeTo: number;
  blockFrom: number;
  blockTo: number;
  sizeOptions: CodeBlockSizeOptions;
}

class ExcalidrawPreviewWidget extends WidgetType {
  private destroyed = false;

  constructor(
    private readonly json: string,
    private codeFrom: number,
    private codeTo: number,
    private readonly sizeOptions: CodeBlockSizeOptions = {},
  ) {
    super();
  }

  eq(other: ExcalidrawPreviewWidget): boolean {
    return other.json === this.json && sizeOptionsEq(other.sizeOptions, this.sizeOptions);
  }

  get estimatedHeight(): number {
    return this.sizeOptions.height ?? 180;
  }

  toDOM(view: EditorView): HTMLElement {
    this.destroyed = false;

    const wrap = document.createElement("div");
    wrap.className = "cm-excalidraw-container";
    applySizeOptions(wrap, this.sizeOptions);

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
        exportPadding: 8,
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

function collectBlocks(state: EditorState): ExcalidrawBlockRef[] {
  const blocks: ExcalidrawBlockRef[] = [];
  syntaxTree(state).iterate({
    enter: (node) => {
      if (node.name !== "FencedCode") return;

      const codeInfoNode = node.node.getChild("CodeInfo");
      if (!codeInfoNode) return false;
      const { lang, options: sizeOptions } = parseCodeBlockInfo(
        state.sliceDoc(codeInfoNode.from, codeInfoNode.to)
      );
      if (lang !== "excalidraw") return false;

      const codeTextNode = node.node.getChild("CodeText");
      const json = codeTextNode
        ? state.sliceDoc(codeTextNode.from, codeTextNode.to).trim()
        : "";

      let codeFrom: number;
      let codeTo: number;
      if (codeTextNode) {
        codeFrom = codeTextNode.from;
        codeTo = codeTextNode.to;
      } else {
        const openFenceLine = state.doc.lineAt(node.from);
        codeFrom = openFenceLine.to + 1;
        codeTo = codeFrom;
      }

      blocks.push({ json, codeFrom, codeTo, blockFrom: node.from, blockTo: node.to, sizeOptions });
      return false;
    },
  });
  return blocks;
}

const excalidrawBlocksField = StateField.define<ExcalidrawBlockRef[]>({
  create: collectBlocks,
  update: (blocks, tr) => (tr.docChanged ? collectBlocks(tr.state) : blocks),
});

const jsonHideLine = Decoration.line({ attributes: { style: "display:none" } });

class JsonPlaceholderWidget extends WidgetType {
  toDOM(): HTMLElement {
    const span = document.createElement("span");
    span.className = "cm-excalidraw-json-placeholder";
    span.textContent = "···";
    return span;
  }
  ignoreEvent(): boolean { return true; }
}

function buildDecorations(state: EditorState): DecorationSet {
  const cursorLine = cursorLineFromState(state);
  const decorations: Range<Decoration>[] = [];

  for (const block of state.field(excalidrawBlocksField)) {
    const startLine = state.doc.lineAt(block.blockFrom);
    const endLine = state.doc.lineAt(block.blockTo);

    if (cursorLine > startLine.number && cursorLine < endLine.number) {
      const jsonStartNum = startLine.number + 1;
      const jsonEndNum = endLine.number - 1;
      if (jsonStartNum <= jsonEndNum) {
        const firstJsonLine = state.doc.line(jsonStartNum);
        decorations.push(
          Decoration.replace({ widget: new JsonPlaceholderWidget() })
            .range(firstJsonLine.from, firstJsonLine.to)
        );
        let pos = firstJsonLine.to + 1;
        const hideEnd = state.doc.line(jsonEndNum).from;
        while (pos <= hideEnd) {
          const line = state.doc.lineAt(pos);
          decorations.push(jsonHideLine.range(line.from));
          pos = line.to + 1;
        }
      }
      continue;
    }

    decorations.push(
      Decoration.replace({
        widget: new ExcalidrawPreviewWidget(block.json, block.codeFrom, block.codeTo, block.sizeOptions),
      }).range(startLine.from, endLine.to)
    );
  }

  return decorations.length > 0 ? Decoration.set(decorations) : Decoration.none;
}

const excalidrawDecorations = makeDecorationField(buildDecorations);

const excalidrawKeymap = keymap.of([
  {
    key: "Mod-Enter",
    run(view: EditorView): boolean {
      const blocks = view.state.field(excalidrawBlocksField);
      const cursor = view.state.selection.main.head;
      const block = blocks.find((b) => b.blockFrom <= cursor && cursor <= b.blockTo);
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

export const excalidrawExtension = [excalidrawBlocksField, excalidrawDecorations, Prec.high(excalidrawKeymap)];
