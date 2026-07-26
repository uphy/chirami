import type { MarkdownConfig } from "@lezer/markdown";
import { syntaxTree } from "@codemirror/language";
import type { EditorView } from "@codemirror/view";
import { tags } from "@lezer/highlight";

// Obsidian-style wiki links: `[[Page]]`, `[[Page|Alias]]`, `[[Page#Heading]]`.
// @lezer/markdown ships no WikiLink node, so we define an inline parser that
// recognises a `[[ ... ]]` run. Parsing happens before the standard Link rule
// so the leading `[[` is not consumed as a normal `[` link bracket.

const CHAR_OPEN = 91; // '['
const CHAR_CLOSE = 93; // ']'

/**
 * MarkdownConfig implementing `[[wiki links]]`. Add to the markdown() extension
 * list alongside GFM/Highlight. The node keeps the brackets as `WikiLinkMark`
 * children so live preview can hide them while leaving the cursor line raw.
 */
export const WikiLink: MarkdownConfig = {
  defineNodes: [
    { name: "WikiLink" },
    { name: "WikiLinkMark", style: tags.processingInstruction },
  ],
  parseInline: [
    {
      name: "WikiLink",
      parse(cx, next, pos) {
        if (next != CHAR_OPEN || cx.char(pos + 1) != CHAR_OPEN) {
          return -1;
        }
        // Scan forward for the closing "]]" within the current inline run.
        let closeStart = -1;
        for (let i = pos + 2; i < cx.end; i++) {
          if (cx.char(i) == CHAR_CLOSE && cx.char(i + 1) == CHAR_CLOSE) {
            closeStart = i;
            break;
          }
        }
        // No close, or empty `[[]]` — not a wiki link.
        if (closeStart < 0 || closeStart === pos + 2) {
          return -1;
        }
        return cx.addElement(
          cx.elt("WikiLink", pos, closeStart + 2, [
            cx.elt("WikiLinkMark", pos, pos + 2),
            cx.elt("WikiLinkMark", closeStart, closeStart + 2),
          ]),
        );
      },
      before: "Link",
    },
  ],
};

/**
 * The raw target of a wiki link covering `pos`, or null when there is none.
 * Returns the inner text (without brackets), e.g. `Page|Alias` or `Page#Heading`.
 * Path/alias/heading splitting is left to the Swift side.
 */
export function wikiLinkTargetAtPosition(view: EditorView, pos: number): string | null {
  const tree = syntaxTree(view.state);
  // Check both resolution sides so clicks on either bracket edge still match.
  for (const side of [-1, 1] as const) {
    for (
      let n: ReturnType<typeof tree.resolve> | null = tree.resolve(pos, side);
      n;
      n = n.parent
    ) {
      if (n.name === "WikiLink") {
        return view.state.sliceDoc(n.from + 2, n.to - 2).trim();
      }
    }
  }
  return null;
}

/** The display text of `[[target|alias]]` (alias if present, else target). */
export function wikiLinkDisplayText(inner: string): string {
  const pipe = inner.indexOf("|");
  return pipe >= 0 ? inner.slice(pipe + 1).trim() : inner.trim();
}
