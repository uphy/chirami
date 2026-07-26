import { createEditor, setEditorContent, setEditorReadOnly, getEditorContext, closeSearch } from "./editor";
import { postToSwift, exposeApi } from "./bridge";
import { applyCapabilities } from "./capabilities";
import { debounce, setWindowActiveEffect } from "./extensions/utils";
import { applyFoldingFromLines } from "./extensions/foldMarkdown";
import { Transaction } from "@codemirror/state";

const container = document.getElementById("editor")!;
let suppressChangeNotification = false;
let windowActive = false;

const debouncedContentChanged = debounce((text: string) => {
  postToSwift({ type: "contentChanged", text });
}, 300);

const view = createEditor(container, {
  // Guard is checked at call time so setContent echo-back is suppressed before debounce.
  onContentChanged: (text) => {
    if (suppressChangeNotification) return;
    debouncedContentChanged(text);
  },
  onCursorChanged: debounce((offset, line) => {
    postToSwift({ type: "cursorChanged", offset, line });
  }, 1000),
  onScrollChanged: debounce((offset) => {
    postToSwift({ type: "scrollChanged", offset });
  }, 1000),
});

let compositionDepth = 0;
const POST_COMPOSITION_RETRY_LIMIT = 10;

function isCompositionActive(): boolean {
  return compositionDepth > 0 || view.composing;
}

function syncCompositionClass(): void {
  view.dom.classList.toggle("chirami-ime-composing", isCompositionActive());
}

function flushDeferredDecorations(): void {
  // livePreview defers rebuilds while IME composition is active. Trigger a no-op
  // transaction after composition ends so pending decorations are recomputed even
  // when no further document change occurs.
  view.dispatch({
    annotations: Transaction.userEvent.of("input.compose.flush"),
  });
}

function scheduleDeferredDecorationFlush(attempt = 0): void {
  window.setTimeout(() => {
    if (isCompositionActive()) {
      if (attempt < POST_COMPOSITION_RETRY_LIMIT) {
        scheduleDeferredDecorationFlush(attempt + 1);
      }
      return;
    }
    syncCompositionClass();
    flushDeferredDecorations();
  }, 0);
}

function resetCompositionState(): void {
  compositionDepth = 0;
  syncCompositionClass();
  scheduleDeferredDecorationFlush();
}

// Composition inside a table cell input is managed by its edit session;
// keep it out of the global (main editor) composition state.
function isFromTableCellInput(e: Event): boolean {
  return !!(e.target as HTMLElement | null)?.closest?.(".cm-table-cell-input");
}

view.contentDOM.addEventListener("compositionstart", (e) => {
  if (isFromTableCellInput(e)) return;
  compositionDepth += 1;
  syncCompositionClass();
});

view.contentDOM.addEventListener("compositionend", (e) => {
  if (isFromTableCellInput(e)) return;
  resetCompositionState();
});

view.contentDOM.addEventListener("blur", () => {
  resetCompositionState();
});

// Recovery guard: on macOS, compositionend can be dropped when the IME is toggled
// via external tools like Karabiner Elements. If CodeMirror reports no active
// composition but our depth counter is still elevated, reset it so the
// chirami-ime-composing class (which hides selection) is cleared.
view.contentDOM.addEventListener("keydown", (e) => {
  if (isFromTableCellInput(e)) return;
  if (compositionDepth > 0 && !view.composing) {
    compositionDepth = 0;
    syncCompositionClass();
    flushDeferredDecorations();
  }
}, true);

exposeApi({
  setContent: (text) => {
    suppressChangeNotification = true;
    try {
      setEditorContent(view, text);
    } finally {
      suppressChangeNotification = false;
    }
  },
  focus: () => { view.focus(); },
  setWindowActive: (active) => {
    if (windowActive === active) return;
    windowActive = active;
    view.dispatch({
      effects: setWindowActiveEffect.of(active),
    });
  },
  setReadOnly: (readOnly) => {
    setEditorReadOnly(view, readOnly);
  },
  closeSearch: () => {
    closeSearch(view);
  },
  setCapabilities: (caps) => {
    applyCapabilities(caps);
  },
  setCursorPosition: (offset) => {
    const docLength = view.state.doc.length;
    const clampedOffset = Math.min(offset, docLength);
    view.dispatch({ selection: { anchor: clampedOffset } });
  },
  setScrollPosition: (offset) => {
    view.scrollDOM.scrollTop = offset;
  },
  insertText: (text) => {
    view.dispatch(view.state.replaceSelection(text));
  },
  setNotePath: (path) => {
    window.__chiramiNotePath = path;
  },
  applyFolding: (lines) => {
    applyFoldingFromLines(view, lines);
  },
  getEditorContext: () => getEditorContext(view),
});

(window as Window & { __chiramiWindowActive?: () => boolean }).__chiramiWindowActive = () => windowActive;

postToSwift({ type: "ready" });
