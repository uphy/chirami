import { syntaxTree } from "@codemirror/language";
import { EditorState, Range, StateEffect, StateField, Transaction } from "@codemirror/state";
import { Decoration, DecorationSet, EditorView, WidgetType } from "@codemirror/view";
import {
  TranscriptBlockRange,
  TranscriptDeviceOption,
  TranscriptDeviceSnapshot,
  TranscriptDevicesListPayload,
  TranscriptDownloadProgress,
  TranscriptErrorPayload,
  TranscriptLevelPayload,
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

interface TranscriptBlockRef {
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
  previewText?: string;
  micDevice: TranscriptDeviceSnapshot;
  systemDevice: TranscriptDeviceSnapshot;
  micLevel: number;
  systemLevel: number;
  downloadProgress?: TranscriptDownloadProgress;
  errorMessage?: string;
  micDevices: TranscriptDeviceOption[];
  systemDevices: TranscriptDeviceOption[];
  separatorInserted: boolean;
  devicesRevision: number;
}

interface TranscriptUiState {
  devicePopoverOpen: boolean;
  deviceRequestSource?: TranscriptSource;
}

interface TranscriptRuntimeUpdate {
  range: TranscriptBlockRange;
  patch: Partial<TranscriptRuntimeState>;
}

const transcriptRuntimeEffect = StateEffect.define<TranscriptRuntimeUpdate>();

function defaultRuntimeState(block: TranscriptBlockRef): TranscriptRuntimeState {
  return {
    status: block.text.trim().length > 0 ? "Completed" : "Idle",
    modelLabel: "Configured model",
    previewText: undefined,
    micDevice: { value: "default", label: "Default" },
    systemDevice: { value: "auto", label: "Auto" },
    micLevel: 0,
    systemLevel: 0,
    micDevices: [],
    systemDevices: [],
    separatorInserted: false,
    devicesRevision: 0,
  };
}

function cloneRuntimeState(runtime: TranscriptRuntimeState): TranscriptRuntimeState {
  return {
    ...runtime,
    micDevice: { ...runtime.micDevice },
    systemDevice: { ...runtime.systemDevice },
    micDevices: runtime.micDevices.map((device) => ({ ...device })),
    systemDevices: runtime.systemDevices.map((device) => ({ ...device })),
    downloadProgress: runtime.downloadProgress ? { ...runtime.downloadProgress } : undefined,
    previewText: runtime.previewText,
  };
}

const transcriptUiState = new Map<number, TranscriptUiState>();

function readUiState(blockFrom: number): TranscriptUiState {
  return transcriptUiState.get(blockFrom) ?? { devicePopoverOpen: false, deviceRequestSource: undefined };
}

function writeUiState(blockFrom: number, patch: TranscriptWidgetUiPatch): void {
  const current = readUiState(blockFrom);
  transcriptUiState.set(blockFrom, {
    devicePopoverOpen: patch.devicePopoverOpen ?? current.devicePopoverOpen,
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

function formatProgress(progress?: TranscriptDownloadProgress): string | null {
  if (!progress) return null;
  const percent = Math.min(100, Math.max(0, progress.fractionCompleted * 100));
  if (progress.totalBytes < 1024 * 1024) {
    return `${percent.toFixed(0)}%`;
  }
  const receivedMb = (progress.receivedBytes / (1024 * 1024)).toFixed(1);
  const totalMb = (progress.totalBytes / (1024 * 1024)).toFixed(1);
  return `${percent.toFixed(0)}% · ${receivedMb}/${totalMb} MB`;
}

function normalizeLevel(level: number): number {
  if (!Number.isFinite(level) || level <= 0) return 0;
  if (level <= 1) return level;
  return Math.min(1, level / 100);
}

function makeMeter(label: string, value: number): HTMLElement {
  const wrap = document.createElement("div");
  wrap.className = "cm-transcript-meter";

  const top = document.createElement("div");
  top.className = "cm-transcript-meter-top";

  const title = document.createElement("span");
  title.className = "cm-transcript-meter-label";
  title.textContent = label;

  const valueEl = document.createElement("span");
  valueEl.className = "cm-transcript-meter-value";
  valueEl.textContent = `${Math.round(normalizeLevel(value) * 100)}%`;

  const bar = document.createElement("div");
  bar.className = "cm-transcript-meter-bar";

  const fill = document.createElement("div");
  fill.className = "cm-transcript-meter-fill";
  fill.style.width = `${Math.round(normalizeLevel(value) * 100)}%`;
  bar.appendChild(fill);

  top.appendChild(title);
  top.appendChild(valueEl);
  wrap.appendChild(top);
  wrap.appendChild(bar);
  return wrap;
}

function buildSelectItem(
  label: string,
  detail: string,
  onClick: () => void,
  active = false,
): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.className = `cm-transcript-device-item${active ? " cm-transcript-device-item--active" : ""}`;
  const labelEl = document.createElement("span");
  labelEl.className = "cm-transcript-device-item-label";
  labelEl.textContent = label;
  const detailEl = document.createElement("span");
  detailEl.className = "cm-transcript-device-item-detail";
  detailEl.textContent = detail;
  button.appendChild(labelEl);
  button.appendChild(detailEl);
  button.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    event.stopPropagation();
    onClick();
  });
  return button;
}

function buildDevicePopover(
  snapshot: TranscriptWidgetSnapshot,
  onSelect: (source: TranscriptSource, value: string, label: string) => void,
): HTMLElement {
  const popover = document.createElement("div");
  popover.className = "cm-transcript-device-popover";

  const title = document.createElement("div");
  title.className = "cm-transcript-device-popover-title";
  title.textContent = "Devices";
  popover.appendChild(title);

  const micHeading = document.createElement("div");
  micHeading.className = "cm-transcript-device-heading";
  micHeading.textContent = "Microphone";
  popover.appendChild(micHeading);

  popover.appendChild(
    buildSelectItem("Default", snapshot.micDevice.label, () => {
      onSelect("mic", "default", "Default");
    }, snapshot.micDevice.value === "default"),
  );

  popover.appendChild(
    buildSelectItem("Request devices", "Ask native layer for available microphones", () => {
      onSelect("mic", "__request__", "Request devices");
    }),
  );

  for (const device of snapshot.micDevices ?? []) {
    popover.appendChild(
      buildSelectItem(device.label, device.detail ?? device.value, () => {
        onSelect("mic", device.value, device.label);
      }, snapshot.micDevice.value === device.value),
    );
  }

  const systemHeading = document.createElement("div");
  systemHeading.className = "cm-transcript-device-heading";
  systemHeading.textContent = "System audio";
  popover.appendChild(systemHeading);

  popover.appendChild(
    buildSelectItem("Auto", snapshot.systemDevice.label, () => {
      onSelect("system", "auto", "Auto");
    }, snapshot.systemDevice.value === "auto"),
  );

  popover.appendChild(
    buildSelectItem("Off", "Do not capture system audio", () => {
      onSelect("system", "off", "Off");
    }, snapshot.systemDevice.value === "off"),
  );

  popover.appendChild(
    buildSelectItem("Request devices", "Ask native layer for available audio processes", () => {
      onSelect("system", "__request__", "Request devices");
    }),
  );

  for (const device of snapshot.systemDevices ?? []) {
    popover.appendChild(
      buildSelectItem(device.label, device.detail ?? device.value, () => {
        onSelect("system", device.value, device.label);
      }, snapshot.systemDevice.value === device.value),
    );
  }

  return popover;
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
  return {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    text: block.text,
    lineCount: block.lineCount,
    status: runtime.status,
    modelLabel: runtime.modelLabel,
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
    devicePopoverOpen: ui.devicePopoverOpen,
    deviceRequestSource: ui.deviceRequestSource,
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

class TranscriptBlockWidget extends WidgetType {
  constructor(
    private readonly snapshot: TranscriptWidgetSnapshot,
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
      other.snapshot.micLevel === this.snapshot.micLevel &&
      other.snapshot.systemLevel === this.snapshot.systemLevel &&
      other.snapshot.errorMessage === this.snapshot.errorMessage &&
      other.snapshot.downloadProgress?.receivedBytes === this.snapshot.downloadProgress?.receivedBytes &&
      other.snapshot.downloadProgress?.totalBytes === this.snapshot.downloadProgress?.totalBytes
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

  ignoreEvent(): boolean {
    return true;
  }
}

function collectBlocks(state: EditorState): TranscriptBlockRef[] {
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
  create: collectBlocks,
  update: (blocks, tr) => (tr.docChanged ? collectBlocks(tr.state) : blocks),
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
        micDevices: effect.value.patch.micDevices ? effect.value.patch.micDevices.map((d) => ({ ...d })) : base.micDevices,
        systemDevices: effect.value.patch.systemDevices ? effect.value.patch.systemDevices.map((d) => ({ ...d })) : base.systemDevices,
        downloadProgress: effect.value.patch.downloadProgress
          ? { ...effect.value.patch.downloadProgress }
          : base.downloadProgress,
        devicesRevision: base.devicesRevision + 1,
      } satisfies TranscriptRuntimeState;
      next.set(key, merged);
    }
    return changed ? next : runtime;
  },
});

const transcriptHideLine = Decoration.line({ attributes: { style: "display:none" } });

function buildDecorations(state: EditorState): DecorationSet {
  const cursorLine = cursorLineFromState(state);
  const runtime = state.field(transcriptRuntimeField);
  const decorations: Range<Decoration>[] = [];

  for (const block of state.field(transcriptBlocksField)) {
    const startLine = state.doc.lineAt(block.blockFrom);
    const endLine = state.doc.lineAt(block.blockTo);
    const cursorInside = cursorLine >= startLine.number && cursorLine <= endLine.number;
    const ui = readUiState(block.blockFrom);
    const keepRenderedWhileInteracting = ui.devicePopoverOpen || ui.deviceRequestSource !== undefined;
    if (cursorInside && !keepRenderedWhileInteracting) {
      continue;
    }

    const snapshot = buildWidgetSnapshot(block, runtime.get(block.blockFrom) ?? defaultRuntimeState(block));
    decorations.push(
      Decoration.widget({
        widget: new TranscriptBlockWidget(snapshot),
        block: true,
        side: -1,
      }).range(startLine.from),
    );

    for (let lineNumber = startLine.number; lineNumber <= endLine.number; lineNumber += 1) {
      decorations.push(transcriptHideLine.range(state.doc.line(lineNumber).from));
    }
  }

  return decorations.length > 0 ? Decoration.set(decorations) : Decoration.none;
}

const transcriptDecorations = StateField.define<DecorationSet>({
  create: buildDecorations,
  update: (decorations, tr) => {
    const needsRebuild =
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

function appendTextBeforeFence(view: EditorView, block: TranscriptBlockRef, insertText: string): void {
  const needsLeadingNewline = block.codeTo > 0 && view.state.sliceDoc(block.codeTo - 1, block.codeTo) !== "\n";
  const text = `${needsLeadingNewline ? "\n" : ""}${insertText.trimEnd()}\n`;
  view.dispatch({
    changes: { from: block.codeTo, to: block.codeTo, insert: text },
    annotations: [Transaction.userEvent.of("input.transcript")],
  });
}

function insertTranscriptSeparator(view: EditorView, block: TranscriptBlockRef): void {
  appendTextBeforeFence(view, block, "---");
}

export function appendTranscriptChunk(view: EditorView, payload: TranscriptChunkPayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  appendTextBeforeFence(view, block, payload.text);
  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch: {
      previewText: undefined,
    },
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
  transcriptUiState.set(block.blockFrom, { devicePopoverOpen: false, deviceRequestSource: undefined });
  view.dispatch({
    changes: { from: block.codeFrom, to: block.codeTo, insert: "" },
    annotations: [Transaction.userEvent.of("input.transcript")],
  });
  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch: {
      status: "Idle",
      previewText: undefined,
      errorMessage: undefined,
      downloadProgress: undefined,
      micLevel: 0,
      systemLevel: 0,
      separatorInserted: false,
    },
  });
  return true;
}

export function updateTranscriptState(view: EditorView, payload: TranscriptStatePayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  const current = view.state.field(transcriptRuntimeField).get(block.blockFrom) ?? defaultRuntimeState(block);

  if (payload.status === "Recording" && current.status === "Completed" && !current.separatorInserted) {
    insertTranscriptSeparator(view, block);
  }

  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch: {
      status: payload.status,
      modelLabel: payload.modelLabel,
      previewText: payload.status === "Recording" ? current.previewText : undefined,
      downloadProgress: payload.status === "Processing" ? current.downloadProgress : undefined,
      micDevice: { ...current.micDevice, label: payload.micDeviceLabel },
      systemDevice: { ...current.systemDevice, label: payload.systemDeviceLabel },
      separatorInserted: payload.status === "Completed" || payload.status === "Idle" || payload.status === "Error"
        ? false
        : current.separatorInserted || payload.status === "Recording",
    },
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
  return true;
}

export function updateTranscriptDevices(view: EditorView, payload: TranscriptDevicesListPayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  writeUiState(block.blockFrom, { devicePopoverOpen: true, deviceRequestSource: undefined });
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
  const updatedBlock = findTranscriptBlock(view.state, payload.range);
  if (updatedBlock) {
    const runtime = view.state.field(transcriptRuntimeField).get(updatedBlock.blockFrom) ?? defaultRuntimeState(updatedBlock);
    const snapshot = buildWidgetSnapshot(updatedBlock, runtime);
    const selector = `.cm-transcript-container[data-block-from="${updatedBlock.blockFrom}"]`;
    const root = document.querySelector(selector) as TranscriptWidgetRoot | null;
    root?.__chiramiTranscriptApplySnapshot?.(snapshot);
  }
  view.requestMeasure();
  return true;
}

export function updateTranscriptModelDownloadProgress(view: EditorView, payload: TranscriptModelDownloadProgressPayload): boolean {
  const block = resolveTranscriptBlock(view.state, payload.range);
  if (!block) return false;
  dispatchRuntimeUpdate(view, {
    range: { blockFrom: block.blockFrom, blockTo: block.blockTo },
    patch: {
      modelLabel: payload.modelLabel,
      downloadProgress: { ...payload.progress },
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
      separatorInserted: false,
    },
  });
  return true;
}

export const transcriptExtension = [transcriptBlocksField, transcriptRuntimeField, transcriptDecorations];
