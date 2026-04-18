// Swift -> JS API and JS -> Swift message types
export interface TranscriptBlockRange {
  blockFrom: number;
  blockTo: number;
}

export type TranscriptSource = "mic" | "system";
export type TranscriptStatus = "Idle" | "Recording" | "Paused" | "Processing" | "Completed" | "Error";

export interface TranscriptDeviceOption {
  value: string;
  label: string;
  detail?: string;
  active?: boolean;
}

export interface TranscriptDeviceSnapshot {
  value: string;
  label: string;
}

export interface TranscriptModelMetadata {
  detail?: string;
  kindLabel?: string;
  configuredLanguage?: string;
  supportedLanguages?: string[];
  installed?: boolean;
  installedSizeBytes?: number;
}

export interface TranscriptDownloadProgress {
  fractionCompleted: number;
  receivedBytes: number;
  totalBytes: number;
  stage: "Downloading" | "Installing" | "Preparing";
}

export interface TranscriptChunkPayload {
  range: TranscriptBlockRange;
  source: TranscriptSource;
  timestamp: number;
  text: string;
}

export interface TranscriptPreviewPayload {
  range: TranscriptBlockRange;
  source: TranscriptSource;
  timestamp: number;
  text: string;
}

export interface TranscriptStatePayload {
  range: TranscriptBlockRange;
  status: TranscriptStatus;
  modelLabel: string;
  micDeviceLabel: string;
  systemDeviceLabel: string;
}

export interface TranscriptLevelPayload {
  range: TranscriptBlockRange;
  source: TranscriptSource;
  level: number;
}

export interface TranscriptDevicesListPayload {
  range: TranscriptBlockRange;
  source: TranscriptSource;
  devices: TranscriptDeviceOption[];
  selectedValue?: string;
}

export interface TranscriptModelStatePayload {
  range: TranscriptBlockRange;
  modelLabel: string;
  selectedValue: string;
  models: TranscriptDeviceOption[];
  metadata?: TranscriptModelMetadata;
}

export interface TranscriptModelDownloadProgressPayload {
  range: TranscriptBlockRange;
  modelLabel: string;
  progress: TranscriptDownloadProgress;
}

export interface TranscriptErrorPayload {
  range: TranscriptBlockRange;
  message: string;
}

export interface EditorTranscriptContextOptions {
  mode: "full" | "last" | "seconds";
  value?: number;
}

export interface EditorContextOptions {
  transcript?: EditorTranscriptContextOptions;
}

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
  getEditorContext: (options?: EditorContextOptions) => string;
  transcriptClearBlock: (range: TranscriptBlockRange) => void;
  transcriptChunk: (payload: TranscriptChunkPayload) => void;
  transcriptPreviewUpdate: (payload: TranscriptPreviewPayload) => void;
  transcriptStateChanged: (payload: TranscriptStatePayload) => void;
  transcriptLevelUpdate: (payload: TranscriptLevelPayload) => void;
  transcriptDevicesList: (payload: TranscriptDevicesListPayload) => void;
  transcriptModelState: (payload: TranscriptModelStatePayload) => void;
  transcriptModelDownloadProgress: (payload: TranscriptModelDownloadProgressPayload) => void;
  transcriptError: (payload: TranscriptErrorPayload) => void;
};

type JsToSwiftMessage =
  | { type: "ready" }
  | { type: "contentChanged"; text: string }
  | { type: "cursorChanged"; offset: number; line: number }
  | { type: "scrollChanged"; offset: number }
  | { type: "openLink"; url: string }
  | { type: "fontSizeChange"; delta: number }
  | { type: "pasteImage"; dataUrl: string }
  | { type: "plainPaste" }
  | { type: "foldChanged"; foldedLines: number[] }
  | { type: "log"; level: "debug" | "info" | "warn" | "error"; message: string }
  | { type: "overlayVisible"; visible: boolean }
  | { type: "pluginStateRequest"; pluginId: string }
  | { type: "pluginStateChanged"; pluginId: string; stateJson: string }
  | { type: "transcriptRecordStart"; range: TranscriptBlockRange; micDevice: TranscriptDeviceSnapshot; systemDevice: TranscriptDeviceSnapshot }
  | { type: "transcriptRecordPause"; range: TranscriptBlockRange }
  | { type: "transcriptRecordResume"; range: TranscriptBlockRange }
  | { type: "transcriptRecordStop"; range: TranscriptBlockRange }
  | { type: "transcriptRecordClear"; range: TranscriptBlockRange }
  | { type: "transcriptLevelMonitorStart"; range: TranscriptBlockRange; micDevice: TranscriptDeviceSnapshot; systemDevice: TranscriptDeviceSnapshot }
  | { type: "transcriptLevelMonitorStop"; range: TranscriptBlockRange }
  | { type: "transcriptDevicesRequest"; range: TranscriptBlockRange; source: TranscriptSource }
  | { type: "transcriptDeviceSelect"; range: TranscriptBlockRange; source: TranscriptSource; value: string; label: string }
  | { type: "transcriptModelRequest"; range: TranscriptBlockRange }
  | { type: "transcriptModelSelect"; range: TranscriptBlockRange; value: string };

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
