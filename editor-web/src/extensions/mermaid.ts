import { syntaxTree } from "@codemirror/language";
import { EditorState, Range } from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  WidgetType,
} from "@codemirror/view";
import mermaid from "mermaid";
import { CodeBlockSizeOptions, applySizeOptions, cursorLineFromState, makeDecorationField, parseCodeBlockInfo, sizeOptionsEq } from "./utils";

// ---------------------------------------------------------------------------
// Theme handling
//
// Mermaid bakes colors into the rendered SVG, so it cannot follow the note
// theme via CSS alone. Instead we resolve the actual --chirami-* custom
// property values (computed through a probe element so color-mix() etc. are
// flattened to concrete colors), feed them to mermaid's "base" theme as
// themeVariables, and re-render live diagrams whenever the theme changes
// (OS light/dark switch or per-note data-chirami-theme attribute).
// ---------------------------------------------------------------------------

interface RGBA {
  r: number;
  g: number;
  b: number;
  a: number;
}

/** Parses computed color strings: "rgb(...)", "rgba(...)", "color(srgb ...)". */
function parseColor(value: string): RGBA | null {
  const rgbMatch = value.match(/^rgba?\((.+)\)$/);
  if (rgbMatch) {
    const parts = rgbMatch[1].split(/[,\s/]+/).filter((p) => p.length > 0);
    if (parts.length < 3) return null;
    const nums = parts.map((p) =>
      p.endsWith("%") ? (parseFloat(p) / 100) * 255 : parseFloat(p),
    );
    if (nums.some((n) => Number.isNaN(n))) return null;
    const a = parts.length >= 4
      ? (parts[3].endsWith("%") ? parseFloat(parts[3]) / 100 : parseFloat(parts[3]))
      : 1;
    return { r: nums[0], g: nums[1], b: nums[2], a };
  }
  const srgbMatch = value.match(
    /^color\(srgb\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)(?:\s*\/\s*([\d.]+%?))?\)$/,
  );
  if (srgbMatch) {
    const a = srgbMatch[4] === undefined
      ? 1
      : srgbMatch[4].endsWith("%")
        ? parseFloat(srgbMatch[4]) / 100
        : parseFloat(srgbMatch[4]);
    return {
      r: parseFloat(srgbMatch[1]) * 255,
      g: parseFloat(srgbMatch[2]) * 255,
      b: parseFloat(srgbMatch[3]) * 255,
      a,
    };
  }
  return null;
}

/** Composites a possibly translucent color over an opaque background. */
function flattenOver(color: RGBA, background: RGBA): RGBA {
  if (color.a >= 1) return color;
  const blend = (c: number, b: number) => c * color.a + b * (1 - color.a);
  return {
    r: blend(color.r, background.r),
    g: blend(color.g, background.g),
    b: blend(color.b, background.b),
    a: 1,
  };
}

function toHex(color: RGBA): string {
  const channel = (n: number) =>
    Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, "0");
  return `#${channel(color.r)}${channel(color.g)}${channel(color.b)}`;
}

function relativeLuminance(color: RGBA): number {
  return (0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b) / 255;
}

interface ResolvedTheme {
  isDark: boolean;
  bg: string;
  text: string;
  accent: string;
  muted: string;
  surface: string;
  surfaceStrong: string;
  fontFamily: string;
}

/**
 * Resolves the note theme colors from CSS custom properties.
 * Uses a probe element so that color-mix() / var() chains are computed
 * to concrete color values by the engine.
 */
function resolveTheme(): ResolvedTheme | null {
  if (typeof document === "undefined" || !document.body) return null;

  const probe = document.createElement("div");
  probe.style.display = "none";
  document.body.appendChild(probe);
  try {
    const resolve = (varName: string): RGBA | null => {
      probe.style.color = `var(${varName})`;
      return parseColor(getComputedStyle(probe).color);
    };

    const bg = resolve("--chirami-bg");
    const text = resolve("--chirami-text");
    if (!bg || !text) return null;
    const accent = resolve("--chirami-accent") ?? text;
    const muted = resolve("--chirami-muted") ?? text;
    const surface = resolve("--chirami-surface") ?? bg;
    const surfaceStrong = resolve("--chirami-surface-strong") ?? surface;

    probe.style.fontFamily = "var(--chirami-font)";
    const fontFamily = getComputedStyle(probe).fontFamily || "sans-serif";

    const opaqueBg = flattenOver(bg, { r: 255, g: 255, b: 255, a: 1 });
    return {
      isDark: relativeLuminance(opaqueBg) < 0.5,
      bg: toHex(opaqueBg),
      text: toHex(flattenOver(text, opaqueBg)),
      accent: toHex(flattenOver(accent, opaqueBg)),
      muted: toHex(flattenOver(muted, opaqueBg)),
      surface: toHex(flattenOver(surface, opaqueBg)),
      surfaceStrong: toHex(flattenOver(surfaceStrong, opaqueBg)),
      fontFamily,
    };
  } finally {
    probe.remove();
  }
}

let appliedThemeKey = "";

/** Re-initializes mermaid when the resolved note theme has changed. */
function syncMermaidTheme(): boolean {
  const theme = resolveTheme();
  if (!theme) return false;
  const key = JSON.stringify(theme);
  if (key === appliedThemeKey) return false;
  appliedThemeKey = key;

  mermaid.initialize({
    startOnLoad: false,
    theme: "base",
    themeVariables: {
      darkMode: theme.isDark,
      background: theme.bg,
      fontFamily: theme.fontFamily,
      // Nodes
      primaryColor: theme.surface,
      primaryTextColor: theme.text,
      primaryBorderColor: theme.muted,
      secondaryColor: theme.surfaceStrong,
      secondaryTextColor: theme.text,
      tertiaryColor: theme.bg,
      tertiaryTextColor: theme.text,
      // Text and lines
      textColor: theme.text,
      lineColor: theme.muted,
      // Edge labels / notes / clusters
      edgeLabelBackground: theme.bg,
      noteBkgColor: theme.surfaceStrong,
      noteTextColor: theme.text,
      noteBorderColor: theme.muted,
      clusterBkg: theme.surfaceStrong,
      clusterBorder: theme.muted,
      titleColor: theme.accent,
    },
  });
  return true;
}

// Initial configuration (overridden by syncMermaidTheme before each render).
mermaid.initialize({ startOnLoad: false, theme: "neutral" });

/** Live diagram containers, re-rendered when the theme changes. */
const liveDiagrams = new Map<HTMLElement, { code: string; view: EditorView }>();

function renderDiagram(container: HTMLElement, code: string, view: EditorView): void {
  syncMermaidTheme();
  // mermaid.render() requires a unique id for internal element creation
  const id = `mermaid-widget-${crypto.randomUUID()}`;
  mermaid
    .render(id, code)
    .then(({ svg }) => {
      if (container.isConnected || liveDiagrams.has(container)) {
        container.innerHTML = svg;
        view.requestMeasure();
      }
    })
    .catch((err: Error) => {
      if (container.isConnected || liveDiagrams.has(container)) {
        container.textContent = err.message;
        container.className = "cm-mermaid-error";
        view.requestMeasure();
      }
    });
}

function rerenderLiveDiagrams(): void {
  if (!syncMermaidTheme()) return;
  for (const [container, { code, view }] of liveDiagrams) {
    renderDiagram(container, code, view);
  }
}

if (typeof document !== "undefined" && typeof window !== "undefined") {
  // OS light/dark appearance switch
  window
    .matchMedia("(prefers-color-scheme: dark)")
    .addEventListener("change", rerenderLiveDiagrams);
  // Per-note theme injected from Swift (data-chirami-theme on <html>)
  new MutationObserver(rerenderLiveDiagrams).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["data-chirami-theme"],
  });
}

class MermaidWidget extends WidgetType {
  constructor(
    private code: string,
    private readonly sizeOptions: CodeBlockSizeOptions = {},
  ) {
    super();
  }

  eq(other: MermaidWidget): boolean {
    return other.code === this.code && sizeOptionsEq(other.sizeOptions, this.sizeOptions);
  }

  toDOM(view: EditorView): HTMLElement {
    const container = document.createElement("div");
    container.className = "cm-mermaid-container";
    applySizeOptions(container, this.sizeOptions);

    liveDiagrams.set(container, { code: this.code, view });
    renderDiagram(container, this.code, view);

    return container;
  }

  destroy(dom: HTMLElement): void {
    liveDiagrams.delete(dom);
  }

  ignoreEvent(): boolean {
    return true;
  }
}

function buildMermaidDecorations(state: EditorState): DecorationSet {
  const cursorLine = cursorLineFromState(state);
  const decorations: Range<Decoration>[] = [];

  syntaxTree(state).iterate({
    enter: (node) => {
      if (node.name !== "FencedCode") return;

      const codeInfoNode = node.node.getChild("CodeInfo");
      if (!codeInfoNode) return false;
      const { lang, options: sizeOptions } = parseCodeBlockInfo(
        state.sliceDoc(codeInfoNode.from, codeInfoNode.to)
      );
      if (lang !== "mermaid") return false;

      const startLine = state.doc.lineAt(node.from);
      const endLine = state.doc.lineAt(node.to);
      if (cursorLine >= startLine.number && cursorLine <= endLine.number) return false;

      const codeTextNode = node.node.getChild("CodeText");
      const code = codeTextNode
        ? state.sliceDoc(codeTextNode.from, codeTextNode.to).trim()
        : "";

      decorations.push(
        Decoration.replace({
          widget: new MermaidWidget(code, sizeOptions),
        }).range(startLine.from, endLine.to),
      );

      return false;
    },
  });

  return decorations.length > 0 ? Decoration.set(decorations) : Decoration.none;
}

export const mermaidExtension = makeDecorationField(buildMermaidDecorations);
