import { EditorState, Transaction } from "@codemirror/state";
import { EditorView, ViewUpdate } from "@codemirror/view";

export type EditorCallbacks = {
  onContentChanged: (text: string) => void;
};

export function createEditor(parent: HTMLElement, callbacks: EditorCallbacks): EditorView {
  const updateListener = EditorView.updateListener.of((update: ViewUpdate) => {
    if (update.docChanged) {
      callbacks.onContentChanged(update.state.doc.toString());
    }
  });

  const state = EditorState.create({
    doc: "",
    extensions: [
      updateListener,
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
