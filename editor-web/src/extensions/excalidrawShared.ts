import type { AppState, BinaryFiles, ExcalidrawElement, LibraryItems } from "@excalidraw/excalidraw";
import { tryParseJSON } from "./utils";

export type ExcalidrawSceneData = {
  elements: readonly ExcalidrawElement[];
  appState?: Partial<AppState>;
  files?: BinaryFiles;
  libraryItems?: LibraryItems;
  scrollX?: number;
  scrollY?: number;
};

export function parseExcalidrawScene(json: string): ExcalidrawSceneData | null {
  const parsed = tryParseJSON<Partial<ExcalidrawSceneData>>(json);
  if (!parsed || !Array.isArray(parsed.elements)) return null;

  return {
    elements: parsed.elements,
    appState: parsed.appState,
    files: parsed.files,
    libraryItems: parsed.libraryItems,
    scrollX: parsed.scrollX,
    scrollY: parsed.scrollY,
  };
}

export function isEmptyExcalidrawScene(json: string): boolean {
  if (!json.trim()) return true;
  const parsed = parseExcalidrawScene(json);
  return parsed ? parsed.elements.length === 0 : false;
}
