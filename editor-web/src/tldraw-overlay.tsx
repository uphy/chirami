import React, { useCallback, useEffect, useMemo, useRef } from "react";
import { createRoot, Root } from "react-dom/client";
import { Tldraw, Editor, TLEditorSnapshot, TLStoreSnapshot } from "tldraw";
import { postToSwift } from "./bridge";
import { tryParseJSON } from "./extensions/utils";

interface TldrawOverlayProps {
  initialSnapshot: string;
  onClose: (snapshot: string) => void;
}

function TldrawOverlay({ initialSnapshot, onClose }: TldrawOverlayProps) {
  const editorRef = useRef<Editor | null>(null);

  const parsedSnapshot = useMemo(
    () => tryParseJSON<TLEditorSnapshot | TLStoreSnapshot>(initialSnapshot),
    [initialSnapshot]
  );

  const handleClose = useCallback(() => {
    const editor = editorRef.current;
    if (!editor) {
      onClose(initialSnapshot);
      return;
    }
    const snapshot = editor.getSnapshot();
    const snapshotJson = JSON.stringify(snapshot);
    if (snapshotJson === initialSnapshot) {
      onClose(initialSnapshot);
    } else {
      onClose(snapshotJson);
    }
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
      <Tldraw
        snapshot={parsedSnapshot}
        darkMode={false}
        onMount={(editor) => {
          editorRef.current = editor;
        }}
      />
      <div
        onClick={handleClose}
        title="Close"
        style={{
          position: "absolute",
          top: 8,
          left: "50%",
          transform: "translateX(-50%)",
          zIndex: 10000,
          display: "flex",
          alignItems: "center",
          gap: 6,
          padding: "5px 12px",
          borderRadius: 8,
          background: "white",
          boxShadow: "0 1px 4px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.06)",
          color: "#555",
          fontSize: 12,
          fontFamily: "system-ui, sans-serif",
          cursor: "pointer",
          userSelect: "none",
          pointerEvents: "auto",
          whiteSpace: "nowrap",
        }}
      >
        <span style={{ fontSize: 14, lineHeight: 1 }}>×</span>
        <span>Close</span>
        <kbd style={{
          padding: "1px 5px",
          borderRadius: 4,
          border: "1px solid #ddd",
          background: "#f5f5f5",
          fontSize: 11,
          color: "#888",
          fontFamily: "inherit",
        }}>Esc</kbd>
      </div>
    </div>
  );
}

let overlayRoot: Root | null = null;
let overlayContainer: HTMLElement | null = null;

export function openTldrawOverlay(
  initialSnapshot: string,
  onClose: (snapshot: string) => void
): void {
  if (overlayContainer) return; // already open

  const container = document.createElement("div");
  container.id = "tldraw-overlay-root";
  document.body.appendChild(container);
  overlayContainer = container;

  overlayRoot = createRoot(container);
  overlayRoot.render(
    <TldrawOverlay
      initialSnapshot={initialSnapshot}
      onClose={(snapshot) => {
        closeTldrawOverlay();
        onClose(snapshot);
      }}
    />
  );
  postToSwift({ type: "overlayVisible", visible: true });
}

export function closeTldrawOverlay(): void {
  overlayRoot?.unmount();
  overlayRoot = null;
  overlayContainer?.remove();
  overlayContainer = null;
  postToSwift({ type: "overlayVisible", visible: false });
}
