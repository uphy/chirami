import { GFM, parser } from "@lezer/markdown";
import type { SyntaxNode } from "@lezer/common";
import { Highlight } from "./highlight";

export const INLINE_FORMAT_MARK_NODES = new Set([
  "EmphasisMark",
  "CodeMark",
  "StrikethroughMark",
  "HighlightMark",
]);

export const INLINE_LINK_MARK_NODES = new Set(["LinkMark", "URL"]);

const inlineMarkdownParser = parser.configure([GFM, Highlight]);

export function renderInlineMarkdown(text: string): DocumentFragment {
  const fragment = document.createDocumentFragment();
  if (text.length === 0) return fragment;

  const tree = inlineMarkdownParser.parse(text);
  const contentNode = tree.topNode.firstChild ?? tree.topNode;
  appendRenderedChildren(fragment, contentNode, text);
  return fragment;
}

function appendRenderedChildren(
  parent: HTMLElement | DocumentFragment,
  node: SyntaxNode,
  text: string,
) {
  let cursor = node.from;

  for (let child = node.firstChild; child; child = child.nextSibling) {
    if (child.from > cursor) {
      parent.appendChild(document.createTextNode(text.slice(cursor, child.from)));
    }

    const renderedChild = renderInlineNode(child, text);
    if (renderedChild) {
      parent.appendChild(renderedChild);
    }

    cursor = child.to;
  }

  if (cursor < node.to) {
    parent.appendChild(document.createTextNode(text.slice(cursor, node.to)));
  }
}

function renderInlineNode(node: SyntaxNode, text: string): Node | null {
  // Backslash escapes (e.g. "\|" in table cells) render without the backslash;
  // the childless Escape node would otherwise fall through to the raw slice.
  if (node.name === "Escape") {
    return document.createTextNode(text.slice(node.from + 1, node.to));
  }

  if (isStandaloneURLNode(node)) {
    const href = text.slice(node.from, node.to);
    const link = document.createElement("a");
    link.href = href;
    link.className = "cm-clickable-link tok-link";
    link.textContent = href;
    return link;
  }

  if (INLINE_FORMAT_MARK_NODES.has(node.name) || INLINE_LINK_MARK_NODES.has(node.name)) {
    return null;
  }

  if (node.name === "StrongEmphasis") {
    return wrapInlineNode("strong", node, text);
  }

  if (node.name === "Emphasis") {
    return wrapInlineNode("em", node, text);
  }

  if (node.name === "Strikethrough") {
    return wrapInlineNode("del", node, text);
  }

  if (node.name === "Highlight") {
    return wrapInlineNode("mark", node, text);
  }

  if (node.name === "InlineCode") {
    const code = wrapInlineNode("code", node, text);
    code.className = "chirami-inline-code";
    return code;
  }

  if (node.name === "Link") {
    const link = document.createElement("a");
    const href = extractLinkHref(node, text);
    if (href) link.href = href;
    link.className = "cm-clickable-link tok-link";
    appendRenderedChildren(link, node, text);
    return link;
  }

  const fragment = document.createDocumentFragment();
  appendRenderedChildren(fragment, node, text);
  return fragment;
}

function wrapInlineNode(tagName: "strong" | "em" | "del" | "code" | "mark", node: SyntaxNode, text: string): HTMLElement {
  const element = document.createElement(tagName);
  appendRenderedChildren(element, node, text);
  return element;
}

function extractLinkHref(node: SyntaxNode, text: string): string | null {
  for (let child = node.firstChild; child; child = child.nextSibling) {
    if (child.name === "URL") {
      return text.slice(child.from, child.to);
    }
  }

  return null;
}

export function isStandaloneURLNode(node: SyntaxNode): boolean {
  return node.name === "URL" && node.parent?.name !== "Link";
}
