import { EditorView } from "@codemirror/view";
import TurndownService from "turndown";
import { gfm } from "turndown-plugin-gfm";
import { postToSwift } from "../bridge";
import { hasCapability } from "../capabilities";

const turndown = new TurndownService({
  headingStyle: "atx",
  codeBlockStyle: "fenced",
  bulletListMarker: "-",
});
turndown.use(gfm);

// Turndown's built-in listItem rule hardcodes space-based indentation:
// "*" + 3 spaces for the marker, and 4 spaces per nesting level. Chirami
// indents with tabs (see `indentUnit.of("\t")` in editor.ts), so pasting HTML
// from Notion or a browser would mix tabs and spaces in the same list — Tab /
// Shift+Tab and the Live Preview depth calculation both misbehave on such
// lines. Emit the house style instead: "- " / "N. " markers, one tab per level.
//
// Tab width is safe for CommonMark nesting: a tab advances to the next multiple
// of 4, which always lands at or past the parent item's content column and
// short of the next one (2 -> 4, 6 -> 8, 10 -> 12, ...).
turndown.addRule("listItem", {
  filter: "li",
  replacement(content, node) {
    const body = content
      .replace(/^\n+/, "")
      .replace(/\n+$/, "\n")
      .replace(/\n/gm, "\n\t");

    const parent = node.parentNode as HTMLElement | null;
    let prefix = "- ";
    if (parent && parent.nodeName === "OL") {
      const start = parent.getAttribute("start");
      const index = Array.prototype.indexOf.call(parent.children, node);
      prefix = `${start ? Number(start) + index : index + 1}. `;
    }

    return prefix + body + (node.nextSibling && !/\n$/.test(body) ? "\n" : "");
  },
});

/** Converts pasted HTML into Chirami-flavored Markdown (tab-indented lists). */
export function htmlToMarkdown(html: string): string {
  return turndown.turndown(html);
}

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

    // 1. Image (only when the host can persist pasted images)
    const imageItem = hasCapability("pasteImage")
      ? Array.from(data.items).find((it) => it.type.startsWith("image/"))
      : undefined;
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
      const md = htmlToMarkdown(html);
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
