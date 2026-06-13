import type { MarkdownConfig, DelimiterType } from "@lezer/markdown";
import { Tag, tags } from "@lezer/highlight";

// Obsidian-style highlight syntax: `==text==` renders as <mark>.
// @lezer/markdown ships no Highlight node, so we define our own delimiter
// modeled on the built-in Strikethrough extension (`~~text~~`). `==` and `~~`
// use distinct delimiter characters, so they never collide.

// Custom tag for highlighted content. The standard `tags` vocabulary has no
// "highlight" entry, so we define one and style it via HighlightStyle in
// editor.ts (mirrors how strikethrough is styled).
export const highlightTag = Tag.define();

const CHAR_EQUALS = 61; // '='
const Punctuation = /[!-/:-@[-`{-~\xA1‐-‧]/;

const HighlightDelim: DelimiterType = { resolve: "Highlight", mark: "HighlightMark" };

/**
 * MarkdownConfig that implements Obsidian-style `==text==` highlight syntax.
 * Add to the markdown() extension list alongside GFM.
 */
export const Highlight: MarkdownConfig = {
  defineNodes: [
    {
      name: "Highlight",
      style: { "Highlight/...": highlightTag },
    },
    {
      name: "HighlightMark",
      style: tags.processingInstruction,
    },
  ],
  parseInline: [
    {
      name: "Highlight",
      parse(cx, next, pos) {
        // Require exactly two '=' (a third '=' immediately after is not a mark).
        if (next != CHAR_EQUALS || cx.char(pos + 1) != CHAR_EQUALS || cx.char(pos + 2) == CHAR_EQUALS) {
          return -1;
        }
        const before = cx.slice(pos - 1, pos);
        const after = cx.slice(pos + 2, pos + 3);
        const sBefore = /\s|^$/.test(before);
        const sAfter = /\s|^$/.test(after);
        const pBefore = Punctuation.test(before);
        const pAfter = Punctuation.test(after);
        return cx.addDelimiter(
          HighlightDelim,
          pos,
          pos + 2,
          !sAfter && (!pAfter || sBefore || pBefore),
          !sBefore && (!pBefore || sAfter || pAfter),
        );
      },
      after: "Emphasis",
    },
  ],
};
