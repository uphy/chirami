import React, { useCallback, useEffect, useMemo, useRef } from "react";
import { createRoot, Root } from "react-dom/client";
import { Excalidraw, serializeAsJSON } from "@excalidraw/excalidraw";
import type { ExcalidrawImperativeAPI } from "@excalidraw/excalidraw/types";
import type { LibraryItems } from "@excalidraw/excalidraw/types";
import { postToSwift, requestPluginState, savePluginState } from "./bridge";
import { tryParseJSON } from "./extensions/utils";
import { EXCALIDRAW_BG_COLOR, parseExcalidrawScene } from "./extensions/excalidrawShared";

const PLUGIN_ID = "excalidraw";
const LIBRARY_SAVE_DEBOUNCE_MS = 150;

// Stable reference — none of these depend on props or state.
const EXCALIDRAW_UI_OPTIONS = {
  canvasActions: {
    loadScene: false,
    saveToActiveFile: false,
    export: false,
    saveAsImage: false,
    // Prevent accidental data loss; undo/redo is available as an alternative.
    clearCanvas: false,
  },
  tools: {
    image: false,
  },
} as const;

type ExcalidrawPluginState = {
  userItems: LibraryItems;
  externalItems: LibraryItems;
};

let librarySaveTimeout: number | null = null;
let pendingLibraryStateJson: string | null = null;

function flushPendingLibraryState(): void {
  if (librarySaveTimeout !== null) {
    window.clearTimeout(librarySaveTimeout);
    librarySaveTimeout = null;
  }
  if (pendingLibraryStateJson === null) return;

  const stateJson = pendingLibraryStateJson;
  pendingLibraryStateJson = null;
  savePluginState(PLUGIN_ID, stateJson);
}

function scheduleLibraryStateSave(stateJson: string): void {
  pendingLibraryStateJson = stateJson;
  if (librarySaveTimeout !== null) {
    window.clearTimeout(librarySaveTimeout);
  }
  librarySaveTimeout = window.setTimeout(() => {
    librarySaveTimeout = null;
    flushPendingLibraryState();
  }, LIBRARY_SAVE_DEBOUNCE_MS);
}

interface ExcalidrawOverlayProps {
  initialSnapshot: string;
  initialLibraryItems: LibraryItems;
  externalItemIds: ReadonlySet<string>;
  onClose: (snapshot: string) => void;
}

function ExcalidrawOverlay({ initialSnapshot, initialLibraryItems, externalItemIds, onClose }: ExcalidrawOverlayProps) {
  const apiRef = useRef<ExcalidrawImperativeAPI | null>(null);
  const libraryReadyRef = useRef(false);

  const initialData = useMemo(() => {
    const scene = parseExcalidrawScene(initialSnapshot);
    const base = scene ?? { elements: [] };
    return {
      ...base,
      appState: { ...base.appState, viewBackgroundColor: EXCALIDRAW_BG_COLOR },
      libraryItems: initialLibraryItems,
    };
  }, [initialLibraryItems, initialSnapshot]);

  const handleClose = useCallback(() => {
    flushPendingLibraryState();

    const api = apiRef.current;
    if (!api) {
      onClose(initialSnapshot);
      return;
    }

    const elements = api.getSceneElements();
    if (elements.length === 0) {
      onClose("");
      return;
    }

    // serializeAsJSON produces pretty-printed JSON; re-stringify to minimize it.
    const snapshotJson = JSON.stringify(
      JSON.parse(serializeAsJSON(elements, api.getAppState(), api.getFiles(), "local"))
    );

    onClose(snapshotJson === initialSnapshot ? initialSnapshot : snapshotJson);
  }, [initialSnapshot, onClose]);

  useEffect(() => {
    const handleKeydown = (e: KeyboardEvent) => {
      if (e.key === "Escape") handleClose();
    };
    document.addEventListener("keydown", handleKeydown);
    return () => document.removeEventListener("keydown", handleKeydown);
  }, [handleClose]);

  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 900, background: EXCALIDRAW_BG_COLOR }}>
      <Excalidraw
        initialData={initialData}
        excalidrawAPI={(api) => {
          apiRef.current = api;
          libraryReadyRef.current = true;
        }}
        onLibraryChange={(items) => {
          if (!libraryReadyRef.current) return;
          const userItems = items.filter((item) => !externalItemIds.has(item.id));
          scheduleLibraryStateSave(JSON.stringify(userItems));
        }}
        aiEnabled={false}
        UIOptions={EXCALIDRAW_UI_OPTIONS}
      />
      <button
        onClick={handleClose}
        type="button"
        aria-label="Close"
        title="Close"
        style={{
          position: "absolute",
          top: 12,
          right: 12,
          zIndex: 10000,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          width: 28,
          height: 28,
          padding: 0,
          borderRadius: 999,
          border: "1px solid rgba(128, 128, 128, 0.35)",
          background: "white",
          boxShadow: "0 1px 4px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.06)",
          color: "#555",
          fontSize: 12,
          fontFamily: "system-ui, sans-serif",
          cursor: "pointer",
          userSelect: "none",
          pointerEvents: "auto",
        }}
      >
        <span style={{ fontSize: 18, lineHeight: 1 }}>×</span>
      </button>
    </div>
  );
}

let overlayRoot: Root | null = null;
let overlayContainer: HTMLElement | null = null;

function parsePluginState(json: string | null): ExcalidrawPluginState {
  if (!json) return { userItems: [], externalItems: [] };
  const state = tryParseJSON<ExcalidrawPluginState>(json);
  return {
    userItems: Array.isArray(state?.userItems) ? state.userItems : [],
    externalItems: Array.isArray(state?.externalItems) ? state.externalItems : [],
  };
}

export function openExcalidrawOverlay(initialSnapshot: string, onClose: (snapshot: string) => void): void {
  if (overlayContainer) return;

  const container = document.createElement("div");
  container.id = "excalidraw-overlay-root";
  document.body.appendChild(container);
  overlayContainer = container;

  requestPluginState(PLUGIN_ID, (stateJson) => {
    const { userItems, externalItems } = parsePluginState(stateJson);
    const allItems = [...externalItems, ...userItems];
    const externalItemIds = new Set(externalItems.map((item) => item.id));

    overlayRoot = createRoot(container);
    overlayRoot.render(
      <ExcalidrawOverlay
        initialSnapshot={initialSnapshot}
        initialLibraryItems={allItems}
        externalItemIds={externalItemIds}
        onClose={(snapshot) => {
          closeExcalidrawOverlay();
          onClose(snapshot);
        }}
      />
    );
    postToSwift({ type: "overlayVisible", visible: true });
  });
}

export function closeExcalidrawOverlay(): void {
  overlayRoot?.unmount();
  overlayRoot = null;
  overlayContainer?.remove();
  overlayContainer = null;
  postToSwift({ type: "overlayVisible", visible: false });
}
