import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { HighlightStyle, foldGutter, syntaxHighlighting, indentUnit } from "@codemirror/language";
import { markdown } from "@codemirror/lang-markdown";
import { yamlFrontmatter } from "@codemirror/lang-yaml";
import { languages } from "@codemirror/language-data";
import { search, searchKeymap, searchPanelOpen, closeSearchPanel } from "@codemirror/search";
import { Compartment, EditorState, Prec, Transaction } from "@codemirror/state";
import { EditorView, ViewUpdate, keymap, drawSelection, placeholder } from "@codemirror/view";
import { GFM } from "@lezer/markdown";
import { classHighlighter, tags } from "@lezer/highlight";
import { chiramiKeymap, openLink, openLinkAtPosition, tightListEnterKeymap, surroundSelectionHandler } from "./extensions/keymap";
import { Highlight, highlightTag } from "./extensions/highlight";
import { livePreview } from "./extensions/livePreview";
import { tableExtension } from "./extensions/table";
import { mermaidExtension } from "./extensions/mermaid";
import { imageExtension } from "./extensions/image";
import { excalidrawExtension } from "./extensions/excalidraw";
import {
  collectTranscriptBlocks,
  parseTranscriptLineTimestampSeconds,
  transcriptImmediateSaveAnnotation,
  transcriptExtension,
  TranscriptBlockRef,
} from "./extensions/transcript";
import { detailsExtension } from "./extensions/details";
import { frontmatterExtension } from "./extensions/frontmatter";
import {
  markdownHeadingFold,
  markdownListFold,
  foldChangeListener,
  applyFoldingFromLines,
} from "./extensions/foldMarkdown";
import { foldedRanges } from "@codemirror/language";
import { smartPaste, plainPasteKeymap } from "./extensions/smartPaste";
import { slashCommandExtension } from "./extensions/slashCommand";
import { foldGutterLineHover } from "./extensions/foldGutterHover";
import { cursorRevealField, windowActiveField } from "./extensions/utils";
import type { EditorContextOptions } from "./bridge";
import { postToSwift } from "./bridge";

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
  { tag: highlightTag, class: "cm-highlight" },
]);

// Compartment so Swift can toggle read-only mode at runtime (e.g. Ad-hoc Notes
// opened with --readonly, which have no save path).
const readOnlyCompartment = new Compartment();

export type EditorCallbacks = {
  onContentChanged: (text: string, immediate: boolean) => void;
  onCursorChanged: (offset: number, line: number) => void;
  onScrollChanged: (offset: number) => void;
};

type EditorContextResult = {
  file: string;
  selection: {
    text: string;
    from: { line: number; column: number };
    to: { line: number; column: number };
  };
  cursor: { line: number; column: number };
  transcript?: {
    text: string;
    truncated: boolean;
  } | null;
};

function resolveContextTranscriptBlock(
  state: EditorState,
  selectionFrom: number,
  selectionTo: number,
  cursor: number,
): TranscriptBlockRef | null {
  const blocks = collectTranscriptBlocks(state);
  if (blocks.length === 0) return null;

  if (selectionFrom !== selectionTo) {
    const selectedBlock = blocks.find((block) => selectionFrom >= block.blockFrom && selectionTo <= block.blockTo);
    if (selectedBlock) return selectedBlock;
  }

  const cursorBlock = blocks.find((block) => cursor >= block.blockFrom && cursor <= block.blockTo);
  if (cursorBlock) return cursorBlock;

  return blocks[blocks.length - 1] ?? null;
}

function buildFilteredTranscriptText(
  text: string,
  options: NonNullable<EditorContextOptions["transcript"]>,
): { text: string; truncated: boolean } {
  const fullText = text.trimEnd();
  if (options.mode === "full") {
    return { text: fullText, truncated: false };
  }

  if (fullText.length === 0) {
    return { text: "", truncated: false };
  }

  const lines = fullText.split(/\r?\n/);
  const utterances = lines
    .map((line, index) => ({
      index,
      timestamp: parseTranscriptLineTimestampSeconds(line.trim()),
    }))
    .filter((entry): entry is { index: number; timestamp: number } => entry.timestamp !== null);

  if (utterances.length === 0) {
    return { text: fullText, truncated: false };
  }

  let selectedIndexes = new Set<number>();
  if (options.mode === "last") {
    const count = options.value ?? 0;
    if (count <= 0) {
      return { text: fullText, truncated: false };
    }
    selectedIndexes = new Set(utterances.slice(-count).map((entry) => entry.index));
  } else {
    const seconds = options.value ?? 0;
    if (seconds <= 0) {
      return { text: fullText, truncated: false };
    }
    const latestTimestamp = Math.max(...utterances.map((entry) => entry.timestamp));
    const threshold = latestTimestamp - seconds;
    selectedIndexes = new Set(
      utterances
        .filter((entry) => entry.timestamp >= threshold)
        .map((entry) => entry.index),
    );
  }

  const filteredLines = lines.filter((_, index) => selectedIndexes.has(index));
  if (filteredLines.length === 0) {
    return { text: "", truncated: fullText.length > 0 };
  }

  return {
    text: filteredLines.join("\n"),
    truncated: filteredLines.length < lines.length,
  };
}

function buildTranscriptContext(
  state: EditorState,
  selectionFrom: number,
  selectionTo: number,
  cursor: number,
  options: NonNullable<EditorContextOptions["transcript"]>,
): EditorContextResult["transcript"] {
  const block = resolveContextTranscriptBlock(state, selectionFrom, selectionTo, cursor);
  if (!block) return null;
  return buildFilteredTranscriptText(block.text, options);
}

export function createEditor(parent: HTMLElement, callbacks: EditorCallbacks): EditorView {
  // Tracks the CodeMirror search panel open state. Mirrored to Swift via the
  // `searchPanelVisible` bridge message so NotePanel can route ESC to JS (close
  // the panel) instead of hiding the note window. Same pattern as `overlayVisible`.
  let searchPanelVisible = false;

  const updateListener = EditorView.updateListener.of((update: ViewUpdate) => {
    if (update.docChanged) {
      const immediate = update.transactions.some((transaction) => {
        return transaction.annotation(transcriptImmediateSaveAnnotation) === true;
      });
      callbacks.onContentChanged(update.state.doc.toString(), immediate);
    }
    if (update.selectionSet) {
      const head = update.state.selection.main.head;
      const line = update.state.doc.lineAt(head).number;
      callbacks.onCursorChanged(head, line);
    }
    const nextSearchPanelVisible = searchPanelOpen(update.state);
    if (nextSearchPanelVisible !== searchPanelVisible) {
      searchPanelVisible = nextSearchPanelVisible;
      postToSwift({ type: "searchPanelVisible", visible: searchPanelVisible });
    }
  });

  const scrollHandler = EditorView.domEventHandlers({
    scroll: (_event, view) => {
      callbacks.onScrollChanged(view.scrollDOM.scrollTop);
      return false;
    },
    mousedown: (event, view) => {
      if (event.button !== 0) return false;
      if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return false;
      const target = event.target;
      if (!(target instanceof Element)) {
        return false;
      }
      const clickedLink = target.closest(".cm-clickable-link");
      if (!(clickedLink instanceof Element)) return false;

      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
      if (pos !== null && view.hasFocus) {
        const cursorLine = view.state.doc.lineAt(view.state.selection.main.head).number;
        const clickedLine = view.state.doc.lineAt(pos).number;
        if (clickedLine === cursorLine) {
          return false;
        }
      }

      const fallbackUrl = clickedLink instanceof HTMLAnchorElement
        ? clickedLink.getAttribute("href")
        : null;
      const opened = pos === null
        ? openLink(fallbackUrl)
        : openLinkAtPosition(view, pos, fallbackUrl);
      if (!opened) return false;

      event.preventDefault();
      return true;
    },
  });

  const state = EditorState.create({
    doc: "",
    extensions: [
      history(),
      search(),
      // Japanese labels for the CodeMirror search/replace panel. Keys match the
      // phrase strings the search extension passes to `state.phrase(...)`.
      EditorState.phrases.of({
        Find: "検索",
        Replace: "置換",
        next: "次へ",
        previous: "前へ",
        all: "すべて",
        "match case": "大文字小文字",
        regexp: "正規表現",
        "by word": "単語単位",
        replace: "置換",
        "replace all": "すべて置換",
        close: "閉じる",
      }),
      indentUnit.of("\t"),
      EditorState.tabSize.of(3),
      readOnlyCompartment.of([]),
      Prec.highest(keymap.of(tightListEnterKeymap)),
      Prec.high(surroundSelectionHandler),
      keymap.of([
        ...plainPasteKeymap,
        ...chiramiKeymap,
        indentWithTab,
        ...defaultKeymap,
        ...historyKeymap,
        ...searchKeymap,
      ]),
      yamlFrontmatter({ content: markdown({ extensions: [GFM, Highlight], codeLanguages: languages }) }),
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
        ".cm-gutters": {
          background: "transparent",
          border: "none",
        },
        ".cm-gutter.cm-foldGutter": {
          width: "14px",
        },
        ".cm-foldGutter .cm-gutterElement": {
          padding: "0",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: "12px",
          color: "var(--chirami-text)",
          cursor: "pointer",
          userSelect: "none",
        },
        ".cm-foldGutter .cm-gutterElement span": {
          opacity: "0",
          transition: "opacity 0.1s",
        },
        ".cm-foldGutter .cm-gutterElement.cm-fold-line-hovered span, .cm-foldGutter .cm-gutterElement:hover span": {
          opacity: "1",
        },
      }),
      drawSelection(),
      placeholder("Write something…"),
      EditorView.lineWrapping,
      windowActiveField,
      cursorRevealField,
      livePreview,
      markdownHeadingFold,
      markdownListFold,
      foldGutter(),
      foldChangeListener,
      foldGutterLineHover,
      tableExtension,
      mermaidExtension,
      imageExtension,
      excalidrawExtension,
      transcriptExtension,
      detailsExtension,
      frontmatterExtension,
      slashCommandExtension,
      smartPaste,
      updateListener,
      scrollHandler,
      EditorView.contentAttributes.of({
        spellcheck: "false",
        autocorrect: "off",
        autocapitalize: "off",
      }),
    ],
  });

  const view = new EditorView({ state, parent });

  // Swift intercepts ESC and, when the search panel is open, re-dispatches a
  // synthetic Escape keydown on `document` (see NoteWebView.dispatchEscapeKey).
  // CodeMirror's searchKeymap Escape only fires while the search input is focused,
  // so we close the panel at the document level instead. The Excalidraw overlay
  // installs its own document keydown listener while open; if its overlay is
  // showing the search panel is closed, so `searchPanelOpen` guards against
  // interfering with that flow.
  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape") return;
    if (!searchPanelOpen(view.state)) return;
    closeSearchPanel(view);
    e.preventDefault();
  });

  return view;
}

/**
 * Closes the CodeMirror search panel if it is open. Used by the host to reset
 * editor state when the note window is hidden, so the panel does not linger on
 * the next show. No-op when the panel is already closed.
 */
export function closeSearch(view: EditorView) {
  if (!searchPanelOpen(view.state)) return;
  closeSearchPanel(view);
}

export function setEditorContent(view: EditorView, text: string) {
  // Preserve fold state across document replacement.
  // Replacing the entire document invalidates all fold ranges in CodeMirror,
  // so we save the folded line numbers and reapply them after the dispatch.
  const ranges = foldedRanges(view.state);
  const foldedLineNumbers: number[] = [];
  if (ranges.size > 0) {
    ranges.between(0, view.state.doc.length, (from) => {
      foldedLineNumbers.push(view.state.doc.lineAt(from).number);
    });
  }

  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: text },
    annotations: [Transaction.userEvent.of("external"), Transaction.addToHistory.of(false)],
  });

  if (foldedLineNumbers.length > 0) {
    applyFoldingFromLines(view, foldedLineNumbers);
  }
}

export function setEditorReadOnly(view: EditorView, readOnly: boolean) {
  view.dispatch({
    effects: readOnlyCompartment.reconfigure(
      readOnly ? [EditorState.readOnly.of(true), EditorView.editable.of(false)] : [],
    ),
  });
}

export function getEditorContext(view: EditorView, options?: EditorContextOptions): string {
  const state = view.state;
  const sel = state.selection.main;
  const head = sel.head;
  const line = state.doc.lineAt(head);
  const fromLine = state.doc.lineAt(sel.from);
  const toLine = state.doc.lineAt(sel.to);
  const context: EditorContextResult = {
    file: window.__chiramiNotePath ?? "",
    selection: {
      text: sel.empty ? "" : state.sliceDoc(sel.from, sel.to),
      from: { line: fromLine.number, column: sel.from - fromLine.from },
      to: { line: toLine.number, column: sel.to - toLine.from },
    },
    cursor: { line: line.number, column: head - line.from },
  };

  if (options?.transcript) {
    context.transcript = buildTranscriptContext(state, sel.from, sel.to, head, options.transcript);
  }

  return JSON.stringify(context);
}
