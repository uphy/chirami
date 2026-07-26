// Swift -> JS API and JS -> Swift message types
type SwiftToJsApi = {
  setContent: (text: string) => void;
  focus: () => void;
  setWindowActive: (active: boolean) => void;
  setReadOnly: (readOnly: boolean) => void;
  closeSearch: () => void;
  setCapabilities: (caps: Partial<import("./capabilities").EditorCapabilities>) => void;
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
  | { type: "openWikiLink"; target: string }
  | { type: "pasteImage"; dataUrl: string }
  | { type: "plainPaste" }
  | { type: "foldChanged"; foldedLines: number[] }
  | { type: "log"; level: "debug" | "info" | "warn" | "error"; message: string }
  | { type: "overlayVisible"; visible: boolean }
  | { type: "searchPanelVisible"; visible: boolean }
  | { type: "pluginStateRequest"; pluginId: string }
  | { type: "pluginStateChanged"; pluginId: string; stateJson: string };

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
    __chiramiPluginReady?: (pluginId: string, stateJson: string | null) => void;
    __chiramiWindowActive?: () => boolean;
  }
}

export function postToSwift(msg: JsToSwiftMessage) {
  window.webkit?.messageHandlers.chirami.postMessage(msg);
}

export function exposeApi(api: SwiftToJsApi) {
  window.chirami = api;
}

// Per-plugin state callbacks, keyed by pluginId.
// Called by Swift via: window.__chiramiPluginReady(pluginId, stateJson)
const pluginStateCallbacks = new Map<string, (json: string | null) => void>();

window.__chiramiPluginReady = (pluginId, stateJson) => {
  const callback = pluginStateCallbacks.get(pluginId);
  if (callback) {
    pluginStateCallbacks.delete(pluginId);
    callback(stateJson);
  }
};

export function requestPluginState(pluginId: string, callback: (json: string | null) => void): void {
  pluginStateCallbacks.set(pluginId, callback);
  postToSwift({ type: "pluginStateRequest", pluginId });
}

export function savePluginState(pluginId: string, stateJson: string): void {
  postToSwift({ type: "pluginStateChanged", pluginId, stateJson });
}
