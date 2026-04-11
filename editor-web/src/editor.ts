import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { markdown } from "@codemirror/lang-markdown";
import { search, searchKeymap } from "@codemirror/search";
import { EditorState, Transaction } from "@codemirror/state";
import { EditorView, ViewUpdate, keymap } from "@codemirror/view";
import { GFM } from "@lezer/markdown";
import { classHighlighter, tags } from "@lezer/highlight";
import { checkboxExtension } from "./extensions/checkbox";
import { chiramiKeymap } from "./extensions/keymap";
import { livePreview } from "./extensions/livePreview";

// Heading font sizes and strikethrough must be set here as inline styles —
// classHighlighter CSS classes alone don't apply font-size to heading lines correctly.
// Use `class` for properties that need CSS variables (background, padding, etc.).
const markdownStyle = HighlightStyle.define([
  { tag: tags.heading1, fontSize: "1.6em", fontWeight: "bold" },
  { tag: tags.heading2, fontSize: "1.4em", fontWeight: "bold" },
  { tag: tags.heading3, fontSize: "1.2em", fontWeight: "bold" },
  { tag: [tags.heading4, tags.heading5, tags.heading6], fontWeight: "bold" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: tags.monospace, class: "chirami-inline-code" },
  { tag: tags.contentSeparator, class: "chirami-hr" },
]);

export type EditorCallbacks = {
  onContentChanged: (text: string) => void;
  onCursorChanged: (offset: number, line: number) => void;
  onScrollChanged: (offset: number) => void;
};

export function createEditor(parent: HTMLElement, callbacks: EditorCallbacks): EditorView {
  const updateListener = EditorView.updateListener.of((update: ViewUpdate) => {
    if (update.docChanged) {
      callbacks.onContentChanged(update.state.doc.toString());
    }
    if (update.selectionSet) {
      const head = update.state.selection.main.head;
      const line = update.state.doc.lineAt(head).number;
      callbacks.onCursorChanged(head, line);
    }
  });

  const scrollHandler = EditorView.domEventHandlers({
    scroll: (_event, view) => {
      callbacks.onScrollChanged(view.scrollDOM.scrollTop);
      return false;
    },
  });

  const state = EditorState.create({
    doc: "",
    extensions: [
      history(),
      search(),
      keymap.of([
        ...chiramiKeymap,
        ...defaultKeymap,
        ...historyKeymap,
        ...searchKeymap,
      ]),
      markdown({ extensions: GFM }),
      syntaxHighlighting(classHighlighter),
      syntaxHighlighting(markdownStyle),
      EditorView.theme({
        ".cm-content": {
          fontFamily: "var(--chirami-font)",
          fontSize: "var(--chirami-font-size)",
        },
        ".cm-line": {
          fontFamily: "var(--chirami-font)",
        },
      }),
      EditorView.lineWrapping,
      livePreview,
      checkboxExtension,
      updateListener,
      scrollHandler,
      EditorView.contentAttributes.of({
        spellcheck: "false",
        autocorrect: "off",
        autocapitalize: "off",
      }),
    ],
  });

  return new EditorView({ state, parent });
}

export function setEditorContent(view: EditorView, text: string) {
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: text },
    annotations: Transaction.userEvent.of("external"),
  });
}
