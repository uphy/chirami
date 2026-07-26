// Tests run in plain Node (no jsdom). Some modules touch `window` at import
// time (e.g. bridge.ts registers window.__chiramiPluginReady), so alias the
// global object before any module under test is imported. This is not a DOM
// shim — tests must stay pure-logic and never rely on document/elements.
if (typeof (globalThis as Record<string, unknown>).window === "undefined") {
  (globalThis as Record<string, unknown>).window = globalThis;
}

export {};
