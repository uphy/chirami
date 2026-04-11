import { postToSwift, exposeApi } from "./bridge";
import { applyCSSVariables, applyFont } from "./theme";

const editor = document.getElementById("editor") as HTMLTextAreaElement;
let debounceTimer: number | null = null;
let suppressNextInput = false;

exposeApi({
  setContent: (text: string) => {
    suppressNextInput = true;
    editor.value = text;
    suppressNextInput = false;
  },
  setTheme: (cssVars: string) => applyCSSVariables(cssVars),
  setFont: (family: string, size: number) => applyFont(family, size),
});

editor.addEventListener("input", () => {
  if (suppressNextInput) return;
  if (debounceTimer !== null) {
    window.clearTimeout(debounceTimer);
  }
  debounceTimer = window.setTimeout(() => {
    postToSwift({ type: "contentChanged", text: editor.value });
    debounceTimer = null;
  }, 300);
});

// Notify Swift that JS is ready
postToSwift({ type: "ready" });
