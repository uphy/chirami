import { syntaxTree } from "@codemirror/language";
import { Annotation, EditorState, Range, StateEffect, StateField, Transaction } from "@codemirror/state";
import { Decoration, DecorationSet, EditorView, WidgetType } from "@codemirror/view";
import {
  TranscriptBlockRange,
  TranscriptDeviceOption,
  TranscriptDeviceSnapshot,
  TranscriptDevicesListPayload,
  TranscriptDownloadProgress,
  TranscriptErrorPayload,
  TranscriptLevelPayload,
  TranscriptModelStatePayload,
  TranscriptStatePayload,
  TranscriptStatus,
  TranscriptSource,
  TranscriptModelDownloadProgressPayload,
  TranscriptChunkPayload,
  TranscriptPreviewPayload,
} from "../bridge";
import { cursorLineFromState, parseCodeBlockInfo } from "./utils";
import {
  createTranscriptWidget,
  TranscriptWidgetUiPatch,
  TranscriptWidgetRuntimePatch,
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

interface TranscriptRuntimeState {
  status: TranscriptStatus;
  modelLabel: string;
  modelValue: string;
  liveText?: string;
  previewText?: string;
  micDevice: TranscriptDeviceSnapshot;
  systemDevice: TranscriptDeviceSnapshot;
  micLevel: number;
  systemLevel: number;
  downloadProgress?: TranscriptDownloadProgress;
  errorMessage?: string;
  models: TranscriptDeviceOption[];
  micDevices: TranscriptDeviceOption[];
  systemDevices: TranscriptDeviceOption[];
  devicesRevision: number;
}

interface TranscriptUiState {
  settingsPanelOpen?: boolean;
  modelDropdownOpen?: boolean;
  deviceDropdownSource?: TranscriptSource;
  deviceRequestSource?: TranscriptSource;
}

export const transcriptImmediateSaveAnnotation = Annotation.define<boolean>();

interface TranscriptRuntimeUpdate {
  range: TranscriptBlockRange;
  patch: Partial<TranscriptRuntimeState>;
}

function hasOwn<K extends PropertyKey>(value: object, key: K): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
}

const transcriptRuntimeEffect = StateEffect.define<TranscriptRuntimeUpdate>();

function defaultRuntimeState(block: TranscriptBlockRef): TranscriptRuntimeState {
  return {
    status: block.text.trim().length > 0 ? "Completed" : "Idle",
    modelLabel: "Configured model",
    modelValue: "",
    previewText: undefined,
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

function cloneRuntimeState(runtime: TranscriptRuntimeState): TranscriptRuntimeState {
  return {
    ...runtime,
    liveText: runtime.liveText,
    micDevice: { ...runtime.micDevice },
    systemDevice: { ...runtime.systemDevice },
    micDevices: runtime.micDevices.map((device) => ({ ...device })),
    systemDevices: runtime.systemDevices.map((device) => ({ ...device })),
    downloadProgress: runtime.downloadProgress ? { ...runtime.downloadProgress } : undefined,
    previewText: runtime.previewText,
    models: runtime.models.map((model) => ({ ...model })),
  };
}

const transcriptUiState = new Map<number, TranscriptUiState>();

function readUiState(blockFrom: number): TranscriptUiState {
  return transcriptUiState.get(blockFrom) ?? {
    settingsPanelOpen: undefined,
    modelDropdownOpen: undefined,
    deviceDropdownSource: undefined,
    deviceRequestSource: undefined,
  };
}

function writeUiState(blockFrom: number, patch: TranscriptWidgetUiPatch): void {
  const current = readUiState(blockFrom);
  transcriptUiState.set(blockFrom, {
    settingsPanelOpen:
      Object.prototype.hasOwnProperty.call(patch, "settingsPanelOpen")
        ? patch.settingsPanelOpen
        : current.settingsPanelOpen,
    modelDropdownOpen:
      Object.prototype.hasOwnProperty.call(patch, "modelDropdownOpen")
        ? patch.modelDropdownOpen
        : current.modelDropdownOpen,
    deviceDropdownSource:
      Object.prototype.hasOwnProperty.call(patch, "deviceDropdownSource")
        ? patch.deviceDropdownSource
        : current.deviceDropdownSource,
    deviceRequestSource:
      Object.prototype.hasOwnProperty.call(patch, "deviceRequestSource")
        ? patch.deviceRequestSource
        : current.deviceRequestSource,
  });
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


function buildPreview(text: string): string {
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter((line) => line.trim().length > 0);
  if (lines.length === 0) {
    return "Press Start to begin a new transcript.";
  }
  const previewLines = lines.slice(0, 3);
  if (lines.length > previewLines.length) {
    previewLines.push("...");
  }
  return previewLines.join("\n");
}

function buildWidgetSnapshot(block: TranscriptBlockRef, runtime: TranscriptRuntimeState): TranscriptWidgetSnapshot {
  const ui = readUiState(block.blockFrom);
  const displayText = runtime.liveText ?? block.text;
  const displayLineCount = displayText.trim().length === 0 ? 0 : displayText.split(/\r?\n/).length;
  return {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    text: displayText,
    lineCount: displayLineCount,
    status: runtime.status,
    modelLabel: runtime.modelLabel,
    currentModelValue: runtime.modelValue,
    models: runtime.models,
    previewText: runtime.previewText,
    micDevice: runtime.micDevice,
    systemDevice: runtime.systemDevice,
    micLevel: runtime.micLevel,
    systemLevel: runtime.systemLevel,
    downloadProgress: runtime.downloadProgress,
    errorMessage: runtime.errorMessage,
    micDevices: runtime.micDevices,
    systemDevices: runtime.systemDevices,
    devicesRevision: runtime.devicesRevision,
    settingsPanelOpen: ui.settingsPanelOpen,
    deviceDropdownSource: ui.deviceDropdownSource,
    deviceRequestSource: ui.deviceRequestSource,
    modelDropdownOpen: ui.modelDropdownOpen,
  };
}

function sameDeviceOptions(left: TranscriptDeviceOption[], right: TranscriptDeviceOption[]): boolean {
  if (left.length !== right.length) return false;
  return left.every((device, index) => {
    const other = right[index];
    return (
      device.value === other.value &&
      device.label === other.label &&
      (device.detail ?? "") === (other.detail ?? "") &&
      (device.active ?? false) === (other.active ?? false)
    );
  });
}

function sameModelOptions(left: TranscriptDeviceOption[], right: TranscriptDeviceOption[]): boolean {
  return sameDeviceOptions(left, right);
}

class TranscriptBlockWidget extends WidgetType {
  constructor(
    private snapshot: TranscriptWidgetSnapshot,
  ) {
    super();
  }

  eq(other: TranscriptBlockWidget): boolean {
    return (
      other.snapshot.text === this.snapshot.text &&
      other.snapshot.lineCount === this.snapshot.lineCount &&
      other.snapshot.range.blockFrom === this.snapshot.range.blockFrom &&
      other.snapshot.range.blockTo === this.snapshot.range.blockTo &&
      other.snapshot.status === this.snapshot.status &&
      other.snapshot.modelLabel === this.snapshot.modelLabel &&
      other.snapshot.currentModelValue === this.snapshot.currentModelValue &&
      other.snapshot.micLevel === this.snapshot.micLevel &&
      other.snapshot.systemLevel === this.snapshot.systemLevel &&
      other.snapshot.errorMessage === this.snapshot.errorMessage &&
      other.snapshot.downloadProgress?.fractionCompleted === this.snapshot.downloadProgress?.fractionCompleted &&
      other.snapshot.downloadProgress?.receivedBytes === this.snapshot.downloadProgress?.receivedBytes &&
      other.snapshot.downloadProgress?.totalBytes === this.snapshot.downloadProgress?.totalBytes &&
      other.snapshot.downloadProgress?.stage === this.snapshot.downloadProgress?.stage &&
      sameModelOptions(other.snapshot.models, this.snapshot.models) &&
      sameDeviceOptions(other.snapshot.micDevices, this.snapshot.micDevices) &&
      sameDeviceOptions(other.snapshot.systemDevices, this.snapshot.systemDevices) &&
      other.snapshot.settingsPanelOpen === this.snapshot.settingsPanelOpen &&
      other.snapshot.modelDropdownOpen === this.snapshot.modelDropdownOpen &&
      other.snapshot.deviceDropdownSource === this.snapshot.deviceDropdownSource &&
      other.snapshot.deviceRequestSource === this.snapshot.deviceRequestSource
    );
  }

  toDOM(_view: EditorView): HTMLElement {
    return createTranscriptWidget(
      this.snapshot,
      (range: TranscriptBlockRange, patch: TranscriptWidgetRuntimePatch) => {
        dispatchRuntimeUpdate(_view, {
          range,
          patch,
        });
      },
      (range: TranscriptBlockRange, patch: TranscriptWidgetUiPatch) => {
        writeUiState(range.blockFrom, patch);
      },
      () => {
        _view.requestMeasure();
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
        const mappedKey = tr.changes.mapPos(key, 1);
        next.set(mappedKey, cloneRuntimeState(value));
        const ui = transcriptUiState.get(key);
        if (ui) {
          transcriptUiState.delete(key);
          transcriptUiState.set(mappedKey, ui);
        }
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
      const current = next.get(key);
      const base = current ?? {
        ...defaultRuntimeState({
          text: "",
          codeFrom: effect.value.range.blockFrom,
          codeTo: effect.value.range.blockFrom,
          blockFrom: effect.value.range.blockFrom,
          blockTo: effect.value.range.blockTo,
          lineCount: 0,
        }),
      };
      const merged = {
        ...base,
        ...effect.value.patch,
        micDevice: effect.value.patch.micDevice ? { ...effect.value.patch.micDevice } : base.micDevice,
        systemDevice: effect.value.patch.systemDevice ? { ...effect.value.patch.systemDevice } : base.systemDevice,
        models: effect.value.patch.models ? effect.value.patch.models.map((d) => ({ ...d })) : base.models,
        micDevices: effect.value.patch.micDevices ? effect.value.patch.micDevices.map((d) => ({ ...d })) : base.micDevices,
        systemDevices: effect.value.patch.systemDevices ? effect.value.patch.systemDevices.map((d) => ({ ...d })) : base.systemDevices,
        previewText: hasOwn(effect.value.patch, "previewText")
          ? effect.value.patch.previewText
          : base.previewText,
        downloadProgress: hasOwn(effect.value.patch, "downloadProgress")
          ? (effect.value.patch.downloadProgress
              ? { ...effect.value.patch.downloadProgress }
              : undefined)
          : base.downloadProgress,
        errorMessage: hasOwn(effect.value.patch, "errorMessage")
          ? effect.value.patch.errorMessage
          : base.errorMessage,
        devicesRevision: base.devicesRevision + 1,
      } satisfies TranscriptRuntimeState;
      next.set(key, merged);
    }
    return changed ? next : runtime;
  },
});

function buildDecorations(state: EditorState): DecorationSet {
  const cursorLine = cursorLineFromState(state);
  const runtime = state.field(transcriptRuntimeField);
  const decorations: Range<Decoration>[] = [];

  for (const block of state.field(transcriptBlocksField)) {
    const startLine = state.doc.lineAt(block.blockFrom);
    const endLine = state.doc.lineAt(block.blockTo);
    const cursorInside = cursorLine >= startLine.number && cursorLine <= endLine.number;
    const ui = readUiState(block.blockFrom);
    const keepRenderedWhileInteracting =
      ui.settingsPanelOpen === true ||
      ui.modelDropdownOpen === true ||
      ui.deviceDropdownSource !== undefined ||
      ui.deviceRequestSource !== undefined;
    if (cursorInside && !keepRenderedWhileInteracting) {
      continue;
    }

    const snapshot = buildWidgetSnapshot(block, runtime.get(block.blockFrom) ?? defaultRuntimeState(block));
    decorations.push(
      Decoration.replace({
        widget: new TranscriptBlockWidget(snapshot),
        block: true,
      }).range(startLine.from, endLine.to),
    );
  }

  return decorations.length > 0 ? Decoration.set(decorations) : Decoration.none;
}

function applySnapshotToRenderedBlock(view: EditorView, range: TranscriptBlockRange): void {
  const updatedBlock = findTranscriptBlock(view.state, range);
  if (!updatedBlock) return;
  const runtime = view.state.field(transcriptRuntimeField).get(updatedBlock.blockFrom) ?? defaultRuntimeState(updatedBlock);
  const snapshot = buildWidgetSnapshot(updatedBlock, runtime);
  const selector = `.cm-transcript-container[data-block-from="${updatedBlock.blockFrom}"]`;
  const root = document.querySelector(selector) as TranscriptWidgetRoot | null;
  root?.__chiramiTranscriptApplySnapshot?.(snapshot);
}

const transcriptDecorations = StateField.define<DecorationSet>({
  create: buildDecorations,
  update: (decorations, tr) => {
    if (tr.annotation(transcriptImmediateSaveAnnotation) === true) {
      return decorations.map(tr.changes);
    }

    const needsRebuild =
      tr.docChanged ||
      tr.startState.selection.main.head !== tr.state.selection.main.head;
    if (needsRebuild) {
      return buildDecorations(tr.state);
    }

    if (tr.effects.some((effect) => effect.is(transcriptRuntimeEffect))) {
      return decorations;
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

function insertTranscriptLineInOrder(rawText: string, payload: TranscriptChunkPayload): string {
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
  view.dispatch({
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
  applySnapshotToRenderedBlock(view, payload.range);
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
  applySnapshotToRenderedBlock(view, payload.range);
  return true;
}

export function clearTranscriptBlock(view: EditorView, range: TranscriptBlockRange): boolean {
  const block = resolveTranscriptBlock(view.state, range);
  if (!block) return false;
  transcriptUiState.set(block.blockFrom, {
    settingsPanelOpen: undefined,
    modelDropdownOpen: undefined,
    deviceDropdownSource: undefined,
    deviceRequestSource: undefined,
  });
  view.dispatch({
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
    },
  });
  applySnapshotToRenderedBlock(view, range);
  return true;
}

export function updateTranscriptState(view: EditorView, payload: TranscriptStatePayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  const current = view.state.field(transcriptRuntimeField).get(block.blockFrom) ?? defaultRuntimeState(block);
  const shouldCommitLiveText = payload.status === "Completed" && current.liveText !== undefined;
  const nextPersistedText = shouldCommitLiveText ? current.liveText : undefined;

  view.dispatch({
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
  const current = view.state.field(transcriptRuntimeField).get(block.blockFrom) ?? defaultRuntimeState(block);
  const patch =
    payload.source === "mic"
      ? { micLevel: payload.level }
      : { systemLevel: payload.level };
  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch,
  });
  applySnapshotToRenderedBlock(view, payload.range);
  return true;
}

export function updateTranscriptDevices(view: EditorView, payload: TranscriptDevicesListPayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  writeUiState(block.blockFrom, { deviceRequestSource: undefined });
  const current = view.state.field(transcriptRuntimeField).get(block.blockFrom) ?? defaultRuntimeState(block);
  const devices = payload.devices.map((device) => ({ ...device }));
  const selectedValue = payload.selectedValue ?? (payload.source === "mic" ? current.micDevice.value : current.systemDevice.value);
  const selectedDevice =
    devices.find((device) => device.value === selectedValue) ??
    devices.find((device) => device.active) ??
    (payload.source === "mic" ? current.micDevice : current.systemDevice);

  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch:
      payload.source === "mic"
        ? {
            micDevices: devices,
            micDevice: { value: selectedDevice.value, label: selectedDevice.label },
          }
        : {
            systemDevices: devices,
            systemDevice: { value: selectedDevice.value, label: selectedDevice.label },
          },
  });
  applySnapshotToRenderedBlock(view, payload.range);
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
      models,
    },
  });
  applySnapshotToRenderedBlock(view, payload.range);
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
  applySnapshotToRenderedBlock(view, payload.range);
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
  applySnapshotToRenderedBlock(view, payload.range);
  return true;
}

export const transcriptExtension = [transcriptBlocksField, transcriptRuntimeField, transcriptDecorations];
