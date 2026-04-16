import { createEditor, setEditorContent, getEditorContext } from "./editor";
import { postToSwift, exposeApi } from "./bridge";
import { debounce } from "./extensions/utils";
import { applyFoldingFromLines } from "./extensions/foldMarkdown";
import {
  appendTranscriptChunk,
  clearTranscriptBlock,
  updateTranscriptDevices,
  updateTranscriptError,
  updateTranscriptLevel,
  updateTranscriptModelDownloadProgress,
  updateTranscriptModelState,
  updateTranscriptPreview,
  updateTranscriptState,
} from "./extensions/transcript";

const container = document.getElementById("editor")!;
let suppressChangeNotification = false;

function logJsError(context: string, error: unknown): void {
  const message =
    error instanceof Error
      ? `${error.name}: ${error.message}\n${error.stack ?? ""}`
      : String(error);
  postToSwift({ type: "log", level: "error", message: `${context}: ${message}` });
}

const debouncedContentChanged = debounce((text: string) => {
  postToSwift({ type: "contentChanged", text });
}, 300);

const view = createEditor(container, {
  // Guard is checked at call time so setContent echo-back is suppressed before debounce.
  onContentChanged: (text, immediate) => {
    if (suppressChangeNotification) return;
    if (immediate) {
      postToSwift({ type: "contentChanged", text });
      return;
    }
    debouncedContentChanged(text);
  },
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
  getEditorContext: (options) => getEditorContext(view, options),
  transcriptClearBlock: (range) => {
    clearTranscriptBlock(view, range);
  },
  transcriptChunk: (payload) => {
    try {
      const appended = appendTranscriptChunk(view, payload);
      if (!appended) {
        postToSwift({
          type: "log",
          level: "error",
          message: `transcriptChunk dropped: blockFrom=${payload.range.blockFrom} blockTo=${payload.range.blockTo}`,
        });
      }
    } catch (error) {
      logJsError("transcriptChunk failed", error);
    }
  },
  transcriptPreviewUpdate: (payload) => {
    try {
      updateTranscriptPreview(view, payload);
    } catch (error) {
      logJsError("transcriptPreviewUpdate failed", error);
    }
  },
  transcriptStateChanged: (payload) => {
    try {
      updateTranscriptState(view, payload);
    } catch (error) {
      logJsError("transcriptStateChanged failed", error);
    }
  },
  transcriptLevelUpdate: (payload) => {
    try {
      updateTranscriptLevel(view, payload);
    } catch (error) {
      logJsError("transcriptLevelUpdate failed", error);
    }
  },
  transcriptDevicesList: (payload) => {
    try {
      window.setTimeout(() => {
        try {
          updateTranscriptDevices(view, payload);
        } catch (error) {
          logJsError("transcriptDevicesList deferred failed", error);
        }
      }, 0);
    } catch (error) {
      logJsError("transcriptDevicesList failed", error);
    }
  },
  transcriptModelState: (payload) => {
    try {
      updateTranscriptModelState(view, payload);
    } catch (error) {
      logJsError("transcriptModelState failed", error);
    }
  },
  transcriptModelDownloadProgress: (payload) => {
    try {
      updateTranscriptModelDownloadProgress(view, payload);
    } catch (error) {
      logJsError("transcriptModelDownloadProgress failed", error);
    }
  },
  transcriptError: (payload) => {
    try {
      updateTranscriptError(view, payload);
    } catch (error) {
      logJsError("transcriptError failed", error);
    }
  },
});

postToSwift({ type: "ready" });
