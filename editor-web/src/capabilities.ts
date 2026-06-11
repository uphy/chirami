/**
 * Editor feature capabilities declared by the Swift host window.
 *
 * Registered Notes enable everything; Ad-hoc Notes (CLI `chirami display`)
 * have no transcript/pasteImage/fold wiring on the Swift side, so the host
 * pushes `false` for those and the editor hides or disables the matching UI
 * instead of sending messages nobody handles.
 *
 * Defaults are all-enabled; the host calls `window.chirami.setCapabilities`
 * before the initial `setContent`, so widgets created during rendering see
 * the final values.
 */
export interface EditorCapabilities {
  transcript: boolean;
  pasteImage: boolean;
  fold: boolean;
}

let current: EditorCapabilities = {
  transcript: true,
  pasteImage: true,
  fold: true,
};

export function applyCapabilities(caps: Partial<EditorCapabilities>): void {
  current = { ...current, ...caps };
}

export function hasCapability(name: keyof EditorCapabilities): boolean {
  return current[name];
}
