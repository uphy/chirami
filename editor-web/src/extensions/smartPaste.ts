import { EditorView } from "@codemirror/view";
import TurndownService from "turndown";
import { gfm } from "turndown-plugin-gfm";
import { postToSwift } from "../bridge";

const turndown = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced" });
turndown.use(gfm);

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

    // 2. HTML
    const html = data.getData("text/html");
    if (html) {
      event.preventDefault();
      const md = turndown.turndown(html);
      view.dispatch(view.state.replaceSelection(md));
      return true;
    }

    // 3. Plain text → default handling
    return false;
  },
});

// Cmd+Shift+V: force plain text paste
export const plainPasteKeymap = [
  {
    key: "Mod-Shift-v",
    run: (view: EditorView) => {
      navigator.clipboard.readText().then((text) => {
        if (text) {
          view.dispatch(view.state.replaceSelection(text));
        }
      });
      return true;
    },
  },
];
