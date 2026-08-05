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

const WORD_CHAR_RE = /[\p{L}\p{N}]/u;

// Turndown escapes every "_" it finds in a text node, so `user_name` lands
// in the note as `user\_name` and the backslash stays visible in Live
// Preview. CommonMark never reads an intraword "_" run as emphasis: such a run
// is both left- and right-flanking and is preceded by a non-punctuation
// character, so it can neither open nor close. The backslash buys nothing and
// costs a wrong character in every identifier pasted from a doc.
//
// Drop the escape only for runs with a letter or digit on both sides. A run at
// either edge of the text node has no known neighbour there — an adjacent
// inline element could supply one — so it stays escaped.
function unescapeIntrawordUnderscores(escaped: string): string {
  let out = "";
  let i = 0;
  while (i < escaped.length) {
    if (escaped[i] !== "\\" || i + 1 >= escaped.length) {
      out += escaped[i];
      i += 1;
      continue;
    }
    if (escaped[i + 1] !== "_") {
      // Copy any other escape pair verbatim, "\\\\" included: consuming both
      // characters keeps a literal backslash from being read as the opener of
      // the escape that follows it.
      out += escaped.slice(i, i + 2);
      i += 2;
      continue;
    }

    let end = i;
    let run = "";
    while (escaped[end] === "\\" && escaped[end + 1] === "_") {
      run += "_";
      end += 2;
    }
    const before = out[out.length - 1];
    const after = escaped[end];
    const intraword =
      before !== undefined &&
      after !== undefined &&
      WORD_CHAR_RE.test(before) &&
      WORD_CHAR_RE.test(after);
    out += intraword ? run : escaped.slice(i, end);
    i = end;
  }
  return out;
}

const escapeMarkdown = turndown.escape.bind(turndown);
turndown.escape = (text: string) => unescapeIntrawordUnderscores(escapeMarkdown(text));

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
