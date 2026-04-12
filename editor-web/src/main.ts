import { createEditor, setEditorContent, getEditorContext } from "./editor";
import { postToSwift, exposeApi } from "./bridge";
import { applyCSSVariables, applyFont } from "./theme";
import { debounce } from "./extensions/utils";
import { applyFoldingFromLines } from "./extensions/foldMarkdown";

const container = document.getElementById("editor")!;
let suppressChangeNotification = false;

const debouncedContentChanged = debounce((text: string) => {
  postToSwift({ type: "contentChanged", text });
}, 300);

const view = createEditor(container, {
  // Guard is checked at call time so setContent echo-back is suppressed before debounce.
  onContentChanged: (text) => { if (!suppressChangeNotification) debouncedContentChanged(text); },
  onCursorChanged: debounce((offset, line) => {
    postToSwift({ type: "cursorChanged", offset, line });
  }, 1000),
  onScrollChanged: debounce((offset) => {
    postToSwift({ type: "scrollChanged", offset });
  }, 1000),
});

exposeApi({
  setContent: (text) => {
    suppressChangeNotification = true;
    try {
      setEditorContent(view, text);
    } finally {
      suppressChangeNotification = false;
    }
  },
  setTheme: applyCSSVariables,
  setFont: applyFont,
  focus: () => { view.focus(); },
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

postToSwift({ type: "ready" });
