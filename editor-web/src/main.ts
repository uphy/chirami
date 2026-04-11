import { createEditor, setEditorContent } from "./editor";
import { postToSwift, exposeApi } from "./bridge";
import { applyCSSVariables, applyFont } from "./theme";

const container = document.getElementById("editor")!;
let debounceTimer: number | null = null;
let suppressChangeNotification = false;

const view = createEditor(container, {
  onContentChanged: (text) => {
    if (suppressChangeNotification) return;
    if (debounceTimer !== null) window.clearTimeout(debounceTimer);
    debounceTimer = window.setTimeout(() => {
      postToSwift({ type: "contentChanged", text });
      debounceTimer = null;
    }, 300);
  },
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
});

postToSwift({ type: "ready" });
