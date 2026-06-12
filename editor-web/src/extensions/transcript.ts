import { syntaxTree } from "@codemirror/language";
import { Annotation, EditorState, Range, StateEffect, StateField, Transaction } from "@codemirror/state";
import { Decoration, DecorationSet, EditorView, WidgetType } from "@codemirror/view";
import {
  TranscriptBlockRange,
  TranscriptDevicesListPayload,
  TranscriptErrorPayload,
  TranscriptLevelPayload,
  TranscriptModelStatePayload,
  TranscriptStatePayload,
  TranscriptModelDownloadProgressPayload,
  TranscriptChunkPayload,
  TranscriptPreviewPayload,
} from "../bridge";
import { cursorLineFromState, parseCodeBlockInfo, transactionCursorRevealChanged, transactionHasWindowActiveEffect } from "./utils";
import {
  createTranscriptWidget,
  sameTranscriptWidgetSnapshot,
  TranscriptWidgetRoot,
  TranscriptWidgetRuntimeState,
  TranscriptWidgetSnapshot,
} from "../transcript-widget";

export interface TranscriptBlockRef {
  text: string;
  codeFrom: number;
  codeTo: number;
  blockFrom: number;
  blockTo: number;
  lineCount: number;
}

/**
 * Single source of truth for per-block transcript state, stored in
 * transcriptRuntimeField keyed by blockFrom. `liveText` is the only field
 * that is not handed to the widget verbatim (it is folded into the snapshot
 * text in buildWidgetSnapshot).
 */
interface TranscriptRuntimeState extends TranscriptWidgetRuntimeState {
  liveText?: string;
}

export const transcriptImmediateSaveAnnotation = Annotation.define<boolean>();

interface TranscriptRuntimeUpdate {
  range: TranscriptBlockRange;
  patch: Partial<TranscriptRuntimeState>;
}

const transcriptRuntimeEffect = StateEffect.define<TranscriptRuntimeUpdate>();

function defaultRuntimeState(block: TranscriptBlockRef): TranscriptRuntimeState {
  return {
    status: block.text.trim().length > 0 ? "Completed" : "Idle",
    modelLabel: "Configured model",
    modelValue: "",
    micDevice: { value: "default", label: "Default" },
    systemDevice: { value: "all", label: "All System Audio" },
    micLevel: 0,
    systemLevel: 0,
    micDevices: [],
    systemDevices: [],
    models: [],
    devicesRevision: 0,
  };
}

function findTranscriptBlock(state: EditorState, range: TranscriptBlockRange): TranscriptBlockRef | undefined {
  const blocks = state.field(transcriptBlocksField);
  return blocks.find((block) => block.blockFrom === range.blockFrom) ?? blocks.find((block) => {
    return range.blockFrom >= block.blockFrom && range.blockFrom <= block.blockTo;
  });
}

function resolveTranscriptBlock(state: EditorState, range: TranscriptBlockRange): TranscriptBlockRef | undefined {
  const exact = findTranscriptBlock(state, range);
  if (exact) return exact;

  const blocks = state.field(transcriptBlocksField);
  if (blocks.length === 1) {
    return blocks[0];
  }

  const runtime = state.field(transcriptRuntimeField, false);
  if (!runtime) return undefined;

  const activeBlock = blocks.find((block) => {
    const current = runtime.get(block.blockFrom);
    return current?.status === "Recording" || current?.status === "Processing" || current?.status === "Paused";
  });
  return activeBlock;
}


function buildWidgetSnapshot(block: TranscriptBlockRef, runtime: TranscriptRuntimeState): TranscriptWidgetSnapshot {
  const { liveText, ...shared } = runtime;
  const displayText = liveText ?? block.text;
  const displayLineCount = displayText.trim().length === 0 ? 0 : displayText.split(/\r?\n/).length;
  return {
    ...shared,
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    text: displayText,
    lineCount: displayLineCount,
  };
}

class TranscriptBlockWidget extends WidgetType {
  constructor(
    private snapshot: TranscriptWidgetSnapshot,
  ) {
    super();
  }

  eq(other: TranscriptBlockWidget): boolean {
    return sameTranscriptWidgetSnapshot(this.snapshot, other.snapshot);
  }

  toDOM(view: EditorView): HTMLElement {
    return createTranscriptWidget(
      this.snapshot,
      (range, patch) => {
        dispatchRuntimeUpdate(view, { range, patch });
      },
      () => {
        view.requestMeasure();
      },
    );
  }

  updateDOM(dom: HTMLElement, _view: EditorView): boolean {
    const root = dom as TranscriptWidgetRoot;
    root.__chiramiTranscriptApplySnapshot?.(this.snapshot);
    return true;
  }

  destroy(dom: HTMLElement): void {
    const root = dom as TranscriptWidgetRoot;
    root.__chiramiTranscriptCleanup?.();
  }

  ignoreEvent(): boolean {
    return true;
  }
}

export function collectTranscriptBlocks(state: EditorState): TranscriptBlockRef[] {
  const blocks: TranscriptBlockRef[] = [];
  syntaxTree(state).iterate({
    enter: (node) => {
      if (node.name !== "FencedCode") return;

      const codeInfoNode = node.node.getChild("CodeInfo");
      if (!codeInfoNode) return false;

      const { lang } = parseCodeBlockInfo(state.sliceDoc(codeInfoNode.from, codeInfoNode.to));
      if (lang !== "transcript") return false;

      const codeTextNode = node.node.getChild("CodeText");
      const text = codeTextNode ? state.sliceDoc(codeTextNode.from, codeTextNode.to).trimEnd() : "";
      const lines = text.trim().length === 0 ? 0 : text.split(/\r?\n/).length;

      const codeFrom = codeTextNode ? codeTextNode.from : state.doc.lineAt(node.from).to + 1;
      const codeTo = codeTextNode ? codeTextNode.to : codeFrom;

      blocks.push({
        text,
        codeFrom,
        codeTo,
        blockFrom: node.from,
        blockTo: node.to,
        lineCount: lines,
      });
      return false;
    },
  });
  return blocks;
}

const transcriptBlocksField = StateField.define<TranscriptBlockRef[]>({
  create: collectTranscriptBlocks,
  update: (blocks, tr) => (tr.docChanged ? collectTranscriptBlocks(tr.state) : blocks),
});

const transcriptRuntimeField = StateField.define<Map<number, TranscriptRuntimeState>>({
  create: () => new Map(),
  update: (runtime, tr) => {
    let next = runtime;
    let changed = false;
    if (tr.docChanged) {
      next = new Map<number, TranscriptRuntimeState>();
      for (const [key, value] of runtime.entries()) {
        next.set(tr.changes.mapPos(key, 1), value);
      }
      changed = true;
    }
    for (const effect of tr.effects) {
      if (!effect.is(transcriptRuntimeEffect)) continue;
      if (!changed) {
        next = new Map(runtime);
        changed = true;
      }
      const key = effect.value.range.blockFrom;
      const base = next.get(key) ?? defaultRuntimeState({
        text: "",
        codeFrom: effect.value.range.blockFrom,
        codeTo: effect.value.range.blockFrom,
        blockFrom: effect.value.range.blockFrom,
        blockTo: effect.value.range.blockTo,
        lineCount: 0,
      });
      // Mechanical merge: patch keys (including ones explicitly set to
      // undefined) override the base by object spread, then the whole record
      // is cloned so stored state never aliases payload objects.
      const merged: TranscriptRuntimeState = structuredClone({ ...base, ...effect.value.patch });
      merged.devicesRevision = base.devicesRevision + 1;
      next.set(key, merged);
    }
    return changed ? next : runtime;
  },
});

function buildDecorations(state: EditorState): DecorationSet {
  const cursorLine = cursorLineFromState(state);
  const runtimeMap = state.field(transcriptRuntimeField);
  const decorations: Range<Decoration>[] = [];

  for (const block of state.field(transcriptBlocksField)) {
    const startLine = state.doc.lineAt(block.blockFrom);
    const endLine = state.doc.lineAt(block.blockTo);
    const cursorInside = cursorLine >= startLine.number && cursorLine <= endLine.number;
    const runtime = runtimeMap.get(block.blockFrom) ?? defaultRuntimeState(block);
    const keepRenderedWhileInteracting =
      runtime.settingsPanelOpen === true ||
      runtime.modelDropdownOpen === true ||
      runtime.deviceDropdownSource !== undefined ||
      runtime.deviceRequestSource !== undefined;
    if (cursorInside && !keepRenderedWhileInteracting) {
      continue;
    }

    decorations.push(
      Decoration.replace({
        widget: new TranscriptBlockWidget(buildWidgetSnapshot(block, runtime)),
        block: true,
      }).range(startLine.from, endLine.to),
    );
  }

  return decorations.length > 0 ? Decoration.set(decorations) : Decoration.none;
}

const transcriptDecorations = StateField.define<DecorationSet>({
  create: buildDecorations,
  update: (decorations, tr) => {
    // Rebuild whenever the doc, the selection, or the runtime state changes.
    // Rendered widgets are kept alive across rebuilds because eq() compares
    // full snapshots and updateDOM() applies the new snapshot to the existing
    // DOM instead of recreating it.
    const needsRebuild =
      transactionHasWindowActiveEffect(tr) ||
      transactionCursorRevealChanged(tr) ||
      tr.docChanged ||
      tr.startState.selection.main.head !== tr.state.selection.main.head ||
      tr.effects.some((effect) => effect.is(transcriptRuntimeEffect));
    if (needsRebuild) {
      return buildDecorations(tr.state);
    }

    return decorations.map(tr.changes);
  },
  provide: (field) => EditorView.decorations.from(field),
});

function dispatchRuntimeUpdate(view: EditorView, update: TranscriptRuntimeUpdate): void {
  view.dispatch({
    effects: transcriptRuntimeEffect.of(update),
  });
}

function dispatchTranscriptContentChange(
  view: EditorView,
  spec: Parameters<EditorView["dispatch"]>[0],
): void {
  if (Array.isArray(spec)) {
    view.dispatch(spec);
    return;
  }
  const previousScrollHeight = view.scrollDOM.scrollHeight;
  const previousClientHeight = view.scrollDOM.clientHeight;
  const previousDistanceFromBottom = Math.max(
    0,
    previousScrollHeight - previousClientHeight - view.scrollDOM.scrollTop,
  );
  const scrollSnapshot = view.scrollSnapshot();
  const mappedSnapshot = spec.changes
    ? (scrollSnapshot.map(view.state.changes(spec.changes)) ?? scrollSnapshot)
    : scrollSnapshot;
  const effects = spec.effects
    ? Array.isArray(spec.effects)
      ? [...spec.effects, mappedSnapshot]
      : [spec.effects, mappedSnapshot]
    : mappedSnapshot;
  view.dispatch({
    ...spec,
    effects,
  });
  if (previousDistanceFromBottom > 24) {
    return;
  }
  const restoreScrollTop = () => {
    const maxScrollTop = Math.max(0, view.scrollDOM.scrollHeight - view.scrollDOM.clientHeight);
    const nextScrollTop = Math.max(0, maxScrollTop - previousDistanceFromBottom);
    if (Math.abs(view.scrollDOM.scrollTop - nextScrollTop) > 0.5) {
      view.scrollDOM.scrollTop = nextScrollTop;
    }
  };
  restoreScrollTop();
  window.requestAnimationFrame(() => {
    restoreScrollTop();
  });
}

export function parseTranscriptLineTimestampSeconds(line: string): number | null {
  const match = line.match(/^\[(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\]\s/);
  if (!match) return null;
  const year = Number.parseInt(match[1] ?? "", 10);
  const month = Number.parseInt(match[2] ?? "", 10);
  const day = Number.parseInt(match[3] ?? "", 10);
  const hour = Number.parseInt(match[4] ?? "", 10);
  const minute = Number.parseInt(match[5] ?? "", 10);
  const second = Number.parseInt(match[6] ?? "", 10);
  if (![year, month, day, hour, minute, second].every(Number.isFinite)) return null;
  return new Date(year, month - 1, day, hour, minute, second).getTime() / 1000;
}

export function insertTranscriptLineInOrder(rawText: string, payload: TranscriptChunkPayload): string {
  const trimmedLine = payload.text.trimEnd();
  if (rawText.length === 0) {
    return `${trimmedLine}\n`;
  }

  const lines = rawText.split("\n");
  const lineStarts: number[] = [];
  let offset = 0;
  for (const line of lines) {
    lineStarts.push(offset);
    offset += line.length + 1;
  }

  let insertOffset = rawText.length;
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index] ?? "";
    const timestamp = parseTranscriptLineTimestampSeconds(line.trim());
    if (timestamp === null) continue;
    if (timestamp > payload.timestamp) {
      insertOffset = lineStarts[index] ?? rawText.length;
      break;
    }
  }

  let insertText = `${trimmedLine}\n`;
  if (insertOffset === rawText.length) {
    const needsLeadingNewline = rawText.length > 0 && rawText.slice(-1) !== "\n";
    if (needsLeadingNewline) {
      insertText = `\n${insertText}`;
    }
  }
  return `${rawText.slice(0, insertOffset)}${insertText}${rawText.slice(insertOffset)}`;
}

export function appendTranscriptChunk(view: EditorView, payload: TranscriptChunkPayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  const current = view.state.field(transcriptRuntimeField).get(block.blockFrom) ?? defaultRuntimeState(block);
  const baseText = current.liveText ?? block.text;
  const nextText = insertTranscriptLineInOrder(baseText, payload);
  dispatchTranscriptContentChange(view, {
    changes: { from: block.codeFrom, to: block.codeTo, insert: nextText },
    annotations: [transcriptImmediateSaveAnnotation.of(true), Transaction.addToHistory.of(false)],
    effects: transcriptRuntimeEffect.of({
      range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
      patch: {
        liveText: nextText,
        previewText: undefined,
      },
    }),
  });
  return true;
}

export function updateTranscriptPreview(view: EditorView, payload: TranscriptPreviewPayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch: {
      previewText: payload.text,
    },
  });
  return true;
}

export function clearTranscriptBlock(view: EditorView, range: TranscriptBlockRange): boolean {
  const block = resolveTranscriptBlock(view.state, range);
  if (!block) return false;
  dispatchTranscriptContentChange(view, {
    changes: { from: block.codeFrom, to: block.codeTo, insert: "" },
    annotations: [transcriptImmediateSaveAnnotation.of(true), Transaction.addToHistory.of(false)],
  });
  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch: {
      status: "Idle",
      liveText: undefined,
      previewText: undefined,
      errorMessage: undefined,
      downloadProgress: undefined,
      micLevel: 0,
      systemLevel: 0,
      settingsPanelOpen: undefined,
      minimized: undefined,
      modelDropdownOpen: undefined,
      deviceDropdownSource: undefined,
      deviceRequestSource: undefined,
    },
  });
  return true;
}

export function updateTranscriptState(view: EditorView, payload: TranscriptStatePayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  const current = view.state.field(transcriptRuntimeField).get(block.blockFrom) ?? defaultRuntimeState(block);
  const shouldCommitLiveText = payload.status === "Completed" && current.liveText !== undefined;
  const nextPersistedText = shouldCommitLiveText ? current.liveText : undefined;

  dispatchTranscriptContentChange(view, {
    ...(nextPersistedText !== undefined
      ? { changes: { from: block.codeFrom, to: block.codeTo, insert: nextPersistedText } }
      : {}),
    ...(nextPersistedText !== undefined
      ? { annotations: [transcriptImmediateSaveAnnotation.of(true), Transaction.addToHistory.of(false)] }
      : {}),
    effects: transcriptRuntimeEffect.of({
      range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
      patch: {
        status: payload.status,
        modelLabel: payload.modelLabel,
        liveText: payload.status === "Recording" || payload.status === "Paused" || payload.status === "Processing"
          ? current.liveText
          : undefined,
        previewText: payload.status === "Recording" ? current.previewText : undefined,
        downloadProgress: payload.status === "Processing" ? current.downloadProgress : undefined,
        micDevice: { ...current.micDevice, label: payload.micDeviceLabel },
        systemDevice: { ...current.systemDevice, label: payload.systemDeviceLabel },
      },
    }),
  });
  return true;
}

export function updateTranscriptLevel(view: EditorView, payload: TranscriptLevelPayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  const patch =
    payload.source === "mic"
      ? { micLevel: payload.level }
      : { systemLevel: payload.level };
  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch,
  });
  return true;
}

export function updateTranscriptDevices(view: EditorView, payload: TranscriptDevicesListPayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  const current = view.state.field(transcriptRuntimeField).get(block.blockFrom) ?? defaultRuntimeState(block);
  const devices = payload.devices.map((device) => ({ ...device }));
  const selectedValue = payload.selectedValue ?? (payload.source === "mic" ? current.micDevice.value : current.systemDevice.value);
  const previousSelection = payload.source === "mic" ? current.micDevice : current.systemDevice;
  const selectedDevice =
    selectedValue === "off"
      ? { value: "off", label: "Off" }
      :
    devices.find((device) => device.value === selectedValue) ??
    devices.find((device) => device.active) ??
    previousSelection;

  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch:
      payload.source === "mic"
        ? {
            micDevices: devices,
            micDevice: { value: selectedDevice.value, label: selectedDevice.label },
            deviceRequestSource: undefined,
          }
        : {
            systemDevices: devices,
            systemDevice: { value: selectedDevice.value, label: selectedDevice.label },
            deviceRequestSource: undefined,
          },
  });
  view.requestMeasure();
  return true;
}

export function updateTranscriptModelState(view: EditorView, payload: TranscriptModelStatePayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  const models = payload.models.map((model) => ({ ...model }));
  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch: {
      modelLabel: payload.modelLabel,
      modelValue: payload.selectedValue,
      modelMetadata: payload.metadata ? { ...payload.metadata } : undefined,
      models,
    },
  });
  view.requestMeasure();
  return true;
}

export function updateTranscriptModelDownloadProgress(view: EditorView, payload: TranscriptModelDownloadProgressPayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  const isClearingProgress =
    payload.progress.fractionCompleted <= 0 &&
    payload.progress.receivedBytes <= 0 &&
    payload.progress.totalBytes === 0;
  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch: {
      modelLabel: payload.modelLabel,
      downloadProgress: isClearingProgress ? undefined : { ...payload.progress },
    },
  });
  return true;
}

export function updateTranscriptError(view: EditorView, payload: TranscriptErrorPayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch: {
      status: "Error",
      previewText: undefined,
      downloadProgress: undefined,
      errorMessage: payload.message,
    },
  });
  return true;
}

export const transcriptExtension = [transcriptBlocksField, transcriptRuntimeField, transcriptDecorations];
