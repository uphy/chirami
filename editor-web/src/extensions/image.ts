import { syntaxTree } from "@codemirror/language";
import { Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  ViewUpdate,
  WidgetType,
} from "@codemirror/view";
import { cursorLineNumber, shouldRebuild } from "./utils";

const RESIZE_EDGE = 16; // px from right edge that triggers resize cursor

type ImageInfo = {
  src: string;
  alt: string;
  width: number | null;
  from: number;
  to: number;
};

class ImageWidget extends WidgetType {
  private deleteBtn: HTMLElement | null = null;
  private abortController: AbortController | null = null;

  constructor(private info: ImageInfo) {
    super();
  }

  eq(other: ImageWidget): boolean {
    return (
      other.info.src === this.info.src &&
      other.info.width === this.info.width &&
      other.info.from === this.info.from
    );
  }

  toDOM(view: EditorView): HTMLElement {
    this.abortController = new AbortController();
    const { signal } = this.abortController;

    const wrap = document.createElement("span");
    wrap.className = "cm-image-widget";

    const img = document.createElement("img");
    img.src = resolveImageSrc(this.info.src);
    img.alt = this.info.alt;
    if (this.info.width !== null) img.style.width = `${this.info.width}px`;
    wrap.appendChild(img);

    const deleteBtn = document.createElement("button");
    deleteBtn.className = "cm-image-delete";
    deleteBtn.textContent = "×";
    deleteBtn.tabIndex = -1;
    deleteBtn.addEventListener("click", () => {
      view.dispatch({
        changes: { from: this.info.from, to: this.info.to, insert: "" },
      });
    });
    document.body.appendChild(deleteBtn);
    this.deleteBtn = deleteBtn;

    const showDelete = () => {
      const rect = img.getBoundingClientRect();
      deleteBtn.style.left = `${rect.right - 28}px`;
      deleteBtn.style.top = `${rect.top + 4}px`;
      deleteBtn.style.opacity = "1";
    };

    const hideDelete = (e: MouseEvent) => {
      const to = e.relatedTarget as Node | null;
      if (to === deleteBtn || to === wrap || to === img) return;
      deleteBtn.style.opacity = "0";
    };

    wrap.addEventListener("mouseenter", showDelete, { signal });
    wrap.addEventListener("mouseleave", hideDelete, { signal });
    deleteBtn.addEventListener("mouseleave", hideDelete, { signal });

    this.attachResize(img, deleteBtn, view, signal);
    return wrap;
  }

  destroy(_dom: HTMLElement) {
    this.abortController?.abort();
    this.abortController = null;
    this.deleteBtn?.remove();
    this.deleteBtn = null;
  }

  private attachResize(img: HTMLImageElement, deleteBtn: HTMLElement, view: EditorView, signal: AbortSignal) {
    let startX = 0;
    let startWidth = 0;
    let dragging = false;
    let rafId: number | null = null;
    let pendingWidth = 0;

    img.addEventListener("pointermove", (e) => {
      if (dragging) return;
      const rect = img.getBoundingClientRect();
      img.style.cursor = e.clientX >= rect.right - RESIZE_EDGE ? "ew-resize" : "";
    }, { signal });

    img.addEventListener("pointerleave", () => {
      if (!dragging) img.style.cursor = "";
    }, { signal });

    img.addEventListener("pointerdown", (e) => {
      const rect = img.getBoundingClientRect();
      if (e.clientX < rect.right - RESIZE_EDGE) return;
      e.preventDefault();
      img.setPointerCapture(e.pointerId);
      dragging = true;
      startX = e.clientX;
      startWidth = img.offsetWidth;
      deleteBtn.style.opacity = "0";
      deleteBtn.style.pointerEvents = "none";
    }, { signal });

    img.addEventListener("pointermove", (e) => {
      if (!dragging || !img.hasPointerCapture(e.pointerId)) return;
      pendingWidth = Math.max(50, startWidth + (e.clientX - startX));
      if (rafId === null) {
        rafId = requestAnimationFrame(() => {
          img.style.width = `${pendingWidth}px`;
          rafId = null;
        });
      }
    }, { signal });

    img.addEventListener("pointerup", (e) => {
      if (!dragging || !img.hasPointerCapture(e.pointerId)) return;
      img.releasePointerCapture(e.pointerId);
      dragging = false;
      img.style.cursor = "";
      if (rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
      const newWidth = Math.max(50, startWidth + (e.clientX - startX));
      img.style.width = `${newWidth}px`;
      this.commitWidth(view, newWidth);
      deleteBtn.style.pointerEvents = "";
    }, { signal });
  }

  private commitWidth(view: EditorView, width: number) {
    const original = view.state.sliceDoc(this.info.from, this.info.to);
    const updated = updateImageWidth(original, width);
    view.dispatch({
      changes: { from: this.info.from, to: this.info.to, insert: updated },
    });
  }

  ignoreEvent(): boolean {
    return false;
  }
}

function resolveImageSrc(src: string): string {
  if (/^https?:/.test(src)) return src;
  if (src.startsWith("data:")) return src;

  const notePath = window.__chiramiNotePath;
  if (src.startsWith("/")) {
    return `chirami-img://${encodeURI(src)}`;
  }
  // Relative path: resolve against note directory
  if (notePath) {
    const noteDir = notePath.substring(0, notePath.lastIndexOf("/"));
    const absolutePath = `${noteDir}/${src}`;
    return `chirami-img://${encodeURI(absolutePath)}`;
  }
  return `chirami-img://${encodeURI(src)}`;
}

function updateImageWidth(markdown: string, width: number): string {
  // Update or add |width to the alt text: ![alt|width](url)
  return markdown.replace(/!\[([^\]]*?)(?:\|\d+)?\]/, (_, alt) => `![${alt}|${Math.round(width)}]`);
}

function parseImageNode(view: EditorView, from: number, to: number): ImageInfo | null {
  const text = view.state.sliceDoc(from, to);
  // Match: ![alt](src) or ![alt|width](src)
  const match = text.match(/^!\[([^\]]*)\]\(([^)]+)\)$/);
  if (!match) return null;

  const rawAlt = match[1];
  const src = match[2].trim();

  // Parse |width from alt
  const widthMatch = rawAlt.match(/^(.*?)\|(\d+)$/);
  const alt = widthMatch ? widthMatch[1] : rawAlt;
  const width = widthMatch ? parseInt(widthMatch[2], 10) : null;

  return { src, alt, width, from, to };
}

class ImagePlugin {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate) {
    if (shouldRebuild(update)) {
      this.decorations = this.build(update.view);
    }
  }

  private build(view: EditorView): DecorationSet {
    const cursorLine = cursorLineNumber(view);
    const decorations: Range<Decoration>[] = [];

    for (const { from, to } of view.visibleRanges) {
      syntaxTree(view.state).iterate({
        from,
        to,
        enter: (node) => {
          if (node.name !== "Image") return;
          const nodeLine = view.state.doc.lineAt(node.from).number;
          if (nodeLine === cursorLine) return;

          const info = parseImageNode(view, node.from, node.to);
          if (!info) return;

          decorations.push(
            Decoration.replace({
              widget: new ImageWidget(info),
            }).range(node.from, node.to),
          );
        },
      });
    }

    return Decoration.set(decorations, true);
  }
}

export const imageExtension = ViewPlugin.fromClass(ImagePlugin, {
  decorations: (v) => v.decorations,
});
