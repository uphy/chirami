import { syntaxTree } from "@codemirror/language";
import { EditorState, TransactionSpec } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import type { SyntaxNode } from "@lezer/common";
import { listLineAt, parsePastedList } from "./listContext";
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
    // Trailing newlines are dropped before indenting: a <p> inside <li> (Google
    // Docs, Notion) ends with "\n\n", and indenting that left a tab-only line
    // between items, turning a tight list loose.
    const body = content
      .replace(/^\n+/, "")
      .replace(/\n+$/, "")
      .replace(/\n/gm, "\n\t");

    const parent = node.parentNode as HTMLElement | null;
    let prefix = "- ";
    if (parent && parent.nodeName === "OL") {
      const start = parent.getAttribute("start");
      const index = Array.prototype.indexOf.call(parent.children, node);
      prefix = `${start ? Number(start) + index : index + 1}. `;
    }

    return prefix + body + (node.nextSibling ? "\n" : "");
  },
});

function styleOf(node: HTMLElement): string {
  return (node.getAttribute("style") ?? "").replace(/\s+/g, "").toLowerCase();
}

// Google Docs wraps the whole clipboard in
// `<b style="font-weight:normal" id="docs-internal-guid-…">`, which Turndown
// would turn into "**" lines around everything. Unwrap it.
turndown.addRule("googleDocsWrapper", {
  filter: (node) =>
    node.nodeName === "B" && (node.getAttribute("id") ?? "").startsWith("docs-internal-guid"),
  replacement: (content) => content,
});

// Google Docs expresses bold/italic as inline styles on <span>.
turndown.addRule("styledSpan", {
  filter: (node) => {
    if (node.nodeName !== "SPAN") return false;
    const style = styleOf(node as HTMLElement);
    return /font-weight:(700|bold)/.test(style) || style.includes("font-style:italic");
  },
  replacement: (content, node) => {
    if (!content.trim()) return content;
    const style = styleOf(node as HTMLElement);
    let out = content;
    if (style.includes("font-style:italic")) out = `*${out}*`;
    if (/font-weight:(700|bold)/.test(style)) out = `**${out}**`;
    return out;
  },
});

// A <br> becomes a plain newline: Chirami shows the source, so CommonMark's
// trailing-two-spaces hard break is only invisible junk at the end of the line.
// Inside a table cell a newline would end the row, so keep the tag there.
turndown.addRule("lineBreak", {
  filter: "br",
  replacement: (_content, node) => {
    for (let p = node.parentNode; p; p = p.parentNode) {
      if (p.nodeName === "TD" || p.nodeName === "TH") return "<br>";
    }
    return "\n";
  },
});

// Slack / GitHub emoji are <img alt=":name:">; keep the shortcode instead of a
// remote image link.
turndown.addRule("emojiImage", {
  filter: (node) => {
    if (node.nodeName !== "IMG") return false;
    const alt = node.getAttribute("alt") ?? "";
    return alt.length > 2 && alt.startsWith(":") && alt.endsWith(":") && !alt.includes(" ");
  },
  replacement: (_content, node) => (node as HTMLElement).getAttribute("alt") ?? "",
});

const TEXT_BULLETS = ["• ", "◦ ", "▪ "];

// Slack copies bullets as literal "• " text lines; make them Markdown list items.
function convertTextBullets(markdown: string): string {
  return markdown
    .split("\n")
    .map((line) => {
      const trimmed = line.trimStart();
      const bullet = TEXT_BULLETS.find((b) => trimmed.startsWith(b));
      if (!bullet) return line;
      return line.slice(0, line.length - trimmed.length) + "- " + trimmed.slice(bullet.length);
    })
    .join("\n");
}

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
  return convertTextBullets(turndown.turndown(html));
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

    const rawPlain = data.getData("text/plain");

    // Inside code, the text is literal: no link wrapping, no HTML conversion.
    if (isInCode(view.state, view.state.selection.main.from)) {
      return false;
    }

    // 2. URL (takes priority over HTML per spec)
    const plainText = rawPlain.trim();
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

    // 3. HTML. Code copied from an editor (VS Code, JetBrains) arrives as
    // `white-space: pre` HTML; converting it would escape `*`/`#`, split every
    // line into a paragraph and drop indentation, so use the plain text.
    const html = data.getData("text/html");
    const text = html && !isPreformattedHtml(html) ? htmlToMarkdown(html) : rawPlain;
    if (!text) return false;

    // 4. Markdown lists are re-indented to fit the list item at the cursor.
    const listInsert = listPasteTransaction(view, text);
    if (listInsert) {
      event.preventDefault();
      view.dispatch(listInsert);
      return true;
    }

    if (text !== rawPlain) {
      event.preventDefault();
      view.dispatch(view.state.replaceSelection(text));
      return true;
    }

    // 5. Plain text → default handling
    return false;
  },
});

const CODE_NODES = new Set(["FencedCode", "CodeBlock", "InlineCode", "CodeText"]);

function isInCode(state: EditorState, pos: number): boolean {
  for (let node: SyntaxNode | null = syntaxTree(state).resolveInner(pos, -1); node; node = node.parent) {
    if (CODE_NODES.has(node.name)) {
      // The opening fence line itself is not "inside" the code.
      if (node.name === "FencedCode" && state.doc.lineAt(node.from).number === state.doc.lineAt(pos).number) {
        return false;
      }
      return true;
    }
  }
  return false;
}

/**
 * True when every visible piece of the HTML sits in preformatted text
 * (`<pre>` or `white-space: pre*`), as editors produce when copying code.
 */
export function isPreformattedHtml(html: string): boolean {
  if (typeof DOMParser === "undefined") return false;
  const doc = new DOMParser().parseFromString(html, "text/html");
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
  let sawText = false;
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (!n.textContent?.trim()) continue;
    sawText = true;
    let pre = false;
    for (let el = n.parentElement; el && el !== doc.body; el = el.parentElement) {
      if (el.tagName === "PRE" || el.style.whiteSpace.startsWith("pre")) {
        pre = true;
        break;
      }
    }
    if (!pre) return false;
  }
  return sawText;
}

/**
 * Builds the transaction for pasting a pure Markdown list. Depths are rebuilt
 * with tabs (Chirami's indent unit) under the indentation of the list item at
 * the cursor:
 * - on an empty item (`- ` only) the item is replaced by the pasted list;
 * - at the end of a non-empty item the list goes on the following lines;
 * - on an empty non-list line the list is inserted at that line's indentation.
 * Returns null when the text is not a list or the cursor is elsewhere, so the
 * caller falls back to a plain insertion.
 */
export function listPasteTransaction(view: EditorView, text: string): TransactionSpec | null {
  const { state } = view;
  const sel = state.selection.main;
  if (!sel.empty) return null;
  const pasted = parsePastedList(text);
  if (!pasted) return null;

  const line = state.doc.lineAt(sel.head);
  const item = listLineAt(state, line);
  const render = (indent: string) =>
    pasted.map((p) => indent + "\t".repeat(p.depth) + p.text).join(state.lineBreak);

  if (item) {
    const contentEmpty = item.contentStart >= line.to;
    if (contentEmpty) {
      const insert = render(item.indent);
      return {
        changes: { from: line.from, to: line.to, insert },
        selection: { anchor: line.from + insert.length },
        scrollIntoView: true,
        userEvent: "input.paste",
      };
    }
    if (sel.head === line.to) {
      const insert = state.lineBreak + render(item.indent);
      return {
        changes: { from: line.to, insert },
        selection: { anchor: line.to + insert.length },
        scrollIntoView: true,
        userEvent: "input.paste",
      };
    }
    return null;
  }

  if (line.text.trim() === "") {
    const insert = render(line.text);
    return {
      changes: { from: line.from, to: line.to, insert },
      selection: { anchor: line.from + insert.length },
      scrollIntoView: true,
      userEvent: "input.paste",
    };
  }
  return null;
}

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
