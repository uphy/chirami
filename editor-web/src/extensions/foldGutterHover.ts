import { EditorView } from "@codemirror/view";

const HOVERED_CLASS = "cm-fold-line-hovered";
const GUTTER_ELEMENT_SELECTOR = ".cm-foldGutter .cm-gutterElement";

let prevLineNumber: number | null = null;

export const foldGutterLineHover = EditorView.domEventHandlers({
  mousemove(event, view) {
    const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
    // pos is null when hovering over the gutter — keep current state to avoid
    // the icon disappearing when the user moves the cursor onto it.
    if (pos === null) return;

    const lineNumber = view.state.doc.lineAt(pos).number;
    if (lineNumber === prevLineNumber) return;
    prevLineNumber = lineNumber;

    const elements = view.dom.querySelectorAll(GUTTER_ELEMENT_SELECTOR);
    elements.forEach((el) => el.classList.remove(HOVERED_CLASS));

    const lineCoords = view.coordsAtPos(pos);
    if (!lineCoords) return;

    const midY = (lineCoords.top + lineCoords.bottom) / 2;
    elements.forEach((el) => {
      const rect = el.getBoundingClientRect();
      if (rect.top <= midY && midY < rect.bottom) {
        el.classList.add(HOVERED_CLASS);
      }
    });
  },
  mouseleave(_event, view) {
    prevLineNumber = null;
    view.dom
      .querySelectorAll(`${GUTTER_ELEMENT_SELECTOR}.${HOVERED_CLASS}`)
      .forEach((el) => el.classList.remove(HOVERED_CLASS));
  },
});
