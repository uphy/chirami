import React, { useCallback, useEffect, useMemo, useRef } from "react";
import { createRoot, Root } from "react-dom/client";
import { Excalidraw, serializeAsJSON } from "@excalidraw/excalidraw";
import type { ExcalidrawImperativeAPI } from "@excalidraw/excalidraw/types";
import { postToSwift } from "./bridge";
import { parseExcalidrawScene } from "./extensions/excalidrawShared";

interface ExcalidrawOverlayProps {
  initialSnapshot: string;
  onClose: (snapshot: string) => void;
}

function ExcalidrawOverlay({ initialSnapshot, onClose }: ExcalidrawOverlayProps) {
  const apiRef = useRef<ExcalidrawImperativeAPI | null>(null);

  const initialData = useMemo(() => parseExcalidrawScene(initialSnapshot), [initialSnapshot]);

  const handleClose = useCallback(() => {
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

    const snapshotJson = serializeAsJSON(elements, api.getAppState(), api.getFiles(), "local");

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
    <div style={{ position: "fixed", inset: 0, zIndex: 9999 }}>
      <Excalidraw
        initialData={initialData}
        excalidrawAPI={(api) => {
          apiRef.current = api;
        }}
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

export function openExcalidrawOverlay(initialSnapshot: string, onClose: (snapshot: string) => void): void {
  if (overlayContainer) return;

  const container = document.createElement("div");
  container.id = "excalidraw-overlay-root";
  document.body.appendChild(container);
  overlayContainer = container;

  overlayRoot = createRoot(container);
  overlayRoot.render(
    <ExcalidrawOverlay
      initialSnapshot={initialSnapshot}
      onClose={(snapshot) => {
        closeExcalidrawOverlay();
        onClose(snapshot);
      }}
    />
  );
  postToSwift({ type: "overlayVisible", visible: true });
}

export function closeExcalidrawOverlay(): void {
  overlayRoot?.unmount();
  overlayRoot = null;
  overlayContainer?.remove();
  overlayContainer = null;
  postToSwift({ type: "overlayVisible", visible: false });
}
