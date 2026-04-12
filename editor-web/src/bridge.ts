// Swift -> JS API and JS -> Swift message types
type SwiftToJsApi = {
  setContent: (text: string) => void;
  setTheme: (cssVars: string) => void;
  setFont: (family: string, size: number) => void;
  focus: () => void;
  setCursorPosition: (offset: number) => void;
  setScrollPosition: (offset: number) => void;
  insertText: (text: string) => void;
  setNotePath: (path: string) => void;
  applyFolding: (lines: number[]) => void;
  getEditorContext: () => string;
};

type JsToSwiftMessage =
  | { type: "ready" }
  | { type: "contentChanged"; text: string }
  | { type: "cursorChanged"; offset: number; line: number }
  | { type: "scrollChanged"; offset: number }
  | { type: "openLink"; url: string }
  | { type: "fontSizeChange"; delta: number }
  | { type: "pasteImage"; dataUrl: string }
  | { type: "foldChanged"; foldedLines: number[] }
  | { type: "log"; level: "debug" | "info" | "warn" | "error"; message: string };

declare global {
  interface Window {
    webkit?: {
      messageHandlers: {
        chirami: {
          postMessage: (msg: JsToSwiftMessage) => void;
        };
      };
    };
    chirami: SwiftToJsApi;
    __chiramiNotePath?: string;
  }
}

export function postToSwift(msg: JsToSwiftMessage) {
  window.webkit?.messageHandlers.chirami.postMessage(msg);
}

export function exposeApi(api: SwiftToJsApi) {
  window.chirami = api;
}
