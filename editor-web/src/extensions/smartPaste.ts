import { EditorView } from "@codemirror/view";
import TurndownService from "turndown";
import { gfm } from "turndown-plugin-gfm";
import { postToSwift } from "../bridge";

const turndown = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced" });
turndown.use(gfm);

function isUrl(text: string): boolean {
  if (text.includes("\n")) return false;
  try {
    const url = new URL(text);
    return (url.protocol === "http:" || url.protocol === "https:") && url.hostname !== "";
  } catch {
    return false;
  }
}

export const smartPaste = EditorView.domEventHandlers({
  paste(event, view) {
    const data = event.clipboardData;
    if (!data) return false;

    // 1. Image
    const imageItem = Array.from(data.items).find((it) => it.type.startsWith("image/"));
    if (imageItem) {
      const file = imageItem.getAsFile();
      if (file) {
        event.preventDefault();
        const reader = new FileReader();
        reader.onload = () => {
          const dataUrl = reader.result as string;
          postToSwift({ type: "pasteImage", dataUrl });
        };
        reader.readAsDataURL(file);
        return true;
      }
    }

    // 2. URL (takes priority over HTML per spec)
    const plainText = data.getData("text/plain").trim();
    if (isUrl(plainText)) {
      event.preventDefault();
      const markdown = `[](${plainText})`;
      const from = view.state.selection.main.from;
      view.dispatch({
        ...view.state.replaceSelection(markdown),
        selection: { anchor: from + 1, head: from + 1 },
      });
      return true;
    }

    // 3. HTML
    const html = data.getData("text/html");
    if (html) {
      event.preventDefault();
      const md = turndown.turndown(html);
      view.dispatch(view.state.replaceSelection(md));
      return true;
    }

    // 4. Plain text → default handling
    return false;
  },
});

// Cmd+Shift+V: force plain text paste via Swift (navigator.clipboard is blocked in WKWebView)
export const plainPasteKeymap = [
  {
    key: "Mod-Shift-v",
    run: (_view: EditorView) => {
      postToSwift({ type: "plainPaste" });
      return true;
    },
  },
];
