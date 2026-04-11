export function applyCSSVariables(cssVars: string) {
  let styleEl = document.getElementById("chirami-theme") as HTMLStyleElement | null;
  if (!styleEl) {
    styleEl = document.createElement("style");
    styleEl.id = "chirami-theme";
    document.head.appendChild(styleEl);
  }
  styleEl.textContent = `:root {\n${cssVars}\n}`;
}

export function applyFont(family: string, size: number) {
  document.documentElement.style.setProperty("--chirami-font", family);
  document.documentElement.style.setProperty("--chirami-font-size", `${size}px`);
}
