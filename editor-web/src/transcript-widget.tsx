import { postToSwift } from "./bridge";
import type {
  TranscriptBlockRange,
  TranscriptDeviceOption,
  TranscriptDeviceSnapshot,
  TranscriptDownloadProgress,
  TranscriptModelMetadata,
  TranscriptSource,
  TranscriptStatus,
} from "./bridge";

export interface TranscriptWidgetSnapshot {
  range: TranscriptBlockRange;
  text: string;
  lineCount: number;
  status: TranscriptStatus;
  modelLabel: string;
  currentModelValue: string;
  modelMetadata?: TranscriptModelMetadata;
  models: TranscriptDeviceOption[];
  previewText?: string;
  micDevice: TranscriptDeviceSnapshot;
  systemDevice: TranscriptDeviceSnapshot;
  micLevel: number;
  systemLevel: number;
  downloadProgress?: TranscriptDownloadProgress;
  errorMessage?: string;
  micDevices: TranscriptDeviceOption[];
  systemDevices: TranscriptDeviceOption[];
  devicesRevision: number;
  settingsPanelOpen?: boolean;
  minimized?: boolean;
  modelDropdownOpen?: boolean;
  deviceDropdownSource?: TranscriptSource;
  deviceRequestSource?: TranscriptSource;
}

export interface TranscriptWidgetRuntimePatch {
  micDevice?: TranscriptDeviceSnapshot;
  systemDevice?: TranscriptDeviceSnapshot;
}

export interface TranscriptWidgetUiPatch {
  settingsPanelOpen?: boolean;
  minimized?: boolean;
  modelDropdownOpen?: boolean;
  deviceDropdownSource?: TranscriptSource;
  deviceRequestSource?: TranscriptSource;
}

export interface TranscriptWidgetRoot extends HTMLElement {
  __chiramiTranscriptApplySnapshot?: (snapshot: TranscriptWidgetSnapshot) => void;
  __chiramiTranscriptRequestMeasure?: () => void;
  __chiramiTranscriptCleanup?: () => void;
}

function normalizeLines(text: string): string[] {
  return text
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter((line) => line.trim().length > 0);
}

function currentSessionLines(text: string): string[] {
  const lines = normalizeLines(text);
  let sessionStart = 0;
  for (let index = 0; index < lines.length; index += 1) {
    if (lines[index]?.trim() === "---") {
      sessionStart = index + 1;
    }
  }
  return lines.slice(sessionStart).filter((line) => line.trim() !== "---");
}

type TranscriptPreviewRow = {
  time: string;
  speaker: string;
  text: string;
  provisional?: boolean;
  latest?: boolean;
};

const transcriptPreviewVisibleRowCount = 5;
const transcriptModalAutoFollowThresholdPx = 64;

function parseTranscriptLine(line: string): TranscriptPreviewRow {
  const match = line.match(/^\[(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})\] ([^:]+): (.+)$/);
  if (!match) {
    return {
      time: "",
      speaker: "",
      text: line,
    };
  }
  return {
    time: match[2] ?? "",
    speaker: match[3] ?? "",
    text: match[4] ?? "",
  };
}

function buildButton(label: string, title: string, onClick: () => void, variant?: string): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.className = `cm-transcript-button${variant ? ` cm-transcript-button--${variant}` : ""}`;
  button.textContent = label;
  button.title = title;
  bindTranscriptPress(button, onClick);
  return button;
}

function suppressTranscriptPress(event: Event): void {
  event.preventDefault();
  event.stopPropagation();
}

function bindTranscriptPress(button: HTMLButtonElement, onClick: () => void): void {
  button.addEventListener("pointerdown", suppressTranscriptPress);
  button.addEventListener("mousedown", suppressTranscriptPress);
  button.addEventListener("click", suppressTranscriptPress);
  button.addEventListener("pointerup", suppressTranscriptPress);
  button.addEventListener("mouseup", suppressTranscriptPress);
  button.addEventListener("pointerdown", (event) => {
    suppressTranscriptPress(event);
    if (button.disabled) return;
    onClick();
  });
}

type TranscriptIconName = "settings" | "clear" | "fullscreen" | "minimize" | "restore";

function buildIconButton(title: string, icon: TranscriptIconName, onClick: () => void): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "cm-transcript-icon-button";
  button.title = title;
  button.setAttribute("aria-label", title);
  bindTranscriptPress(button, onClick);

  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  svg.classList.add("cm-transcript-icon-button-svg");

  if (icon === "settings") {
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute(
      "d",
      "M19.14 12.94c.04-.31.06-.63.06-.94s-.02-.63-.06-.94l2.03-1.58a.5.5 0 0 0 .12-.64l-1.92-3.32a.5.5 0 0 0-.6-.22l-2.39.96a7.1 7.1 0 0 0-1.63-.94l-.36-2.54a.5.5 0 0 0-.5-.42h-3.84a.5.5 0 0 0-.5.42l-.36 2.54c-.58.22-1.12.53-1.63.94l-2.39-.96a.5.5 0 0 0-.6.22L2.7 8.84a.5.5 0 0 0 .12.64l2.03 1.58c-.04.31-.06.63-.06.94s.02.63.06.94L2.82 14.52a.5.5 0 0 0-.12.64l1.92 3.32a.5.5 0 0 0 .6.22l2.39-.96c.5.4 1.05.72 1.63.94l.36 2.54a.5.5 0 0 0 .5.42h3.84a.5.5 0 0 0 .5-.42l.36-2.54c.58-.22 1.13-.54 1.63-.94l2.39.96a.5.5 0 0 0 .6-.22l1.92-3.32a.5.5 0 0 0-.12-.64l-2.03-1.58ZM12 15.5A3.5 3.5 0 1 1 12 8.5a3.5 3.5 0 0 1 0 7Z",
    );
    path.setAttribute("fill", "currentColor");
    svg.appendChild(path);
  } else {
    svg.setAttribute("fill", "none");
    svg.setAttribute("stroke", "currentColor");
    svg.setAttribute("stroke-width", "1.8");
    svg.setAttribute("stroke-linecap", "round");
    svg.setAttribute("stroke-linejoin", "round");

    const pathA = document.createElementNS("http://www.w3.org/2000/svg", "path");
    const pathB = document.createElementNS("http://www.w3.org/2000/svg", "path");
    if (icon === "clear") {
      pathA.setAttribute("d", "M3 6h18");
      pathB.setAttribute("d", "M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M6 6l1 14a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-14");
    } else if (icon === "fullscreen") {
      pathA.setAttribute("d", "M9 3H5a2 2 0 0 0-2 2v4M15 3h4a2 2 0 0 1 2 2v4");
      pathB.setAttribute("d", "M21 15v4a2 2 0 0 1-2 2h-4M3 15v4a2 2 0 0 0 2 2h4");
    } else if (icon === "restore") {
      pathA.setAttribute("d", "M4 14l6 6M4 20h6v-6");
      pathB.setAttribute("d", "M20 10l-6-6M20 4h-6v6");
    } else {
      pathA.setAttribute("d", "M20 14h-6v6M14 14l6 6");
      pathB.setAttribute("d", "M4 10h6V4M10 10L4 4");
    }
    svg.appendChild(pathA);
    svg.appendChild(pathB);
  }
  button.appendChild(svg);

  return button;
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
    suppressTranscriptPress(event);
    onClick();
  });
  button.addEventListener("mousedown", suppressTranscriptPress);
  button.addEventListener("click", suppressTranscriptPress);
  button.addEventListener("pointerup", suppressTranscriptPress);
  button.addEventListener("mouseup", suppressTranscriptPress);
  button.addEventListener("keydown", (event) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    suppressTranscriptPress(event);
    onClick();
  });
  return button;
}

function buildFallbackPreview(
  text: string,
  status: TranscriptStatus,
  previewText?: string,
  progress?: TranscriptDownloadProgress,
): string {
  const lines = currentSessionLines(text);
  if (previewText && previewText.trim().length > 0 && status === "Recording") {
    return previewText.trim();
  }
  if (lines.length === 0) {
    switch (status) {
      case "Recording":
        return "Recording in progress...";
      case "Paused":
        return "Recording paused.";
      case "Processing":
        if (!progress) return "Finalizing transcript...";
        switch (progress.stage) {
          case "Installing":
            return "Installing speech model...";
          case "Preparing":
            return "Preparing speech engine...";
          case "Downloading":
          default:
            return "Downloading speech model...";
        }
      case "Completed":
        return "Transcript completed.";
      case "Error":
        return "Transcript failed.";
      case "Idle":
      default:
        return "Press Start to begin a new transcript.";
    }
  }
  const previewLines = lines.slice(0, 3);
  if (lines.length > previewLines.length) {
    previewLines.push("...");
  }
  return previewLines.join("\n");
}

function buildTranscriptPreviewRows(
  text: string,
  status: TranscriptStatus,
  previewText?: string,
): TranscriptPreviewRow[] {
  const committedLines = normalizeLines(text);
  const visibleCommitted = committedLines.map((line) => parseTranscriptLine(line));
  const provisional = previewText?.trim();
  if (provisional && status === "Recording") {
    return [
      ...visibleCommitted,
      { time: "", speaker: "Live", text: provisional, provisional: true, latest: true },
    ];
  }
  if (visibleCommitted.length > 0) {
    visibleCommitted[visibleCommitted.length - 1]!.latest = true;
  }
  return visibleCommitted;
}

function buildPreviewLayoutSignature(
  text: string,
  status: TranscriptStatus,
  previewText?: string,
  progressStage?: TranscriptDownloadProgress["stage"],
  hasError = false,
): string {
  const rows = buildTranscriptPreviewRows(text, status, previewText);
  return JSON.stringify({
    isEmpty: rows.length === 0,
    status,
    progressStage: progressStage ?? "",
    hasError,
  });
}

function latestTranscriptRow(rows: TranscriptPreviewRow[]): TranscriptPreviewRow | undefined {
  for (let index = rows.length - 1; index >= 0; index -= 1) {
    const row = rows[index];
    if (row?.latest) return row;
  }
  return rows[rows.length - 1];
}

type RenderTranscriptRowsOptions = {
  compact?: boolean;
  padToCount?: number;
  showHeader?: boolean;
};

function renderTranscriptRows(
  target: HTMLElement,
  rows: TranscriptPreviewRow[],
  options: RenderTranscriptRowsOptions = {},
): void {
  const table = document.createElement("div");
  table.className = "cm-transcript-preview-table";
  if (options.compact) {
    table.classList.add("cm-transcript-preview-table--compact");
  }
  if (options.showHeader) {
    const headerRow = document.createElement("div");
    headerRow.className = "cm-transcript-preview-row cm-transcript-preview-row--header";
    for (const label of ["Time", "Speaker", "Text"]) {
      const cell = document.createElement("div");
      cell.className = "cm-transcript-preview-cell";
      cell.textContent = label;
      headerRow.appendChild(cell);
    }
    table.appendChild(headerRow);
  }

  const rowsToRender = [...rows];
  const padToCount = options.padToCount ?? 0;
  while (rowsToRender.length < padToCount) {
    rowsToRender.push({ time: "", speaker: "", text: "" });
  }

  for (const row of rowsToRender) {
    const isPlaceholder = row.time === "" && row.speaker === "" && row.text === "" && !row.provisional && !row.latest;
    const rowEl = document.createElement("div");
    rowEl.className = "cm-transcript-preview-row";
    if (row.latest) {
      rowEl.classList.add("cm-transcript-preview-row--latest");
    }
    if (row.provisional) {
      rowEl.classList.add("cm-transcript-preview-row--provisional");
    }
    if (isPlaceholder) {
      rowEl.classList.add("cm-transcript-preview-row--placeholder");
    }

    const timeEl = document.createElement("div");
    timeEl.className = "cm-transcript-preview-cell cm-transcript-preview-cell--time";
    timeEl.textContent = isPlaceholder ? "\u00a0" : row.time || "…";

    const speakerEl = document.createElement("div");
    speakerEl.className = "cm-transcript-preview-cell cm-transcript-preview-cell--speaker";
    speakerEl.textContent = isPlaceholder ? "\u00a0" : row.speaker || "—";
    if (!isPlaceholder) {
      const normalizedSpeaker = row.speaker.trim().toLowerCase();
      if (normalizedSpeaker === "you") {
        speakerEl.classList.add("cm-transcript-preview-cell--speaker-self");
      } else if (normalizedSpeaker === "live") {
        speakerEl.classList.add("cm-transcript-preview-cell--speaker-live");
      }
    }

    const textEl = document.createElement("div");
    textEl.className = "cm-transcript-preview-cell cm-transcript-preview-cell--text";
    textEl.textContent = isPlaceholder ? "\u00a0" : row.text;

    rowEl.appendChild(timeEl);
    rowEl.appendChild(speakerEl);
    rowEl.appendChild(textEl);
    table.appendChild(rowEl);
  }

  target.replaceChildren(table);
}

function renderTranscriptModalContent(
  target: HTMLElement,
  text: string,
  status: TranscriptStatus,
  previewText?: string,
  progress?: TranscriptDownloadProgress,
): void {
  const rows = buildTranscriptPreviewRows(text, status, previewText);
  if (rows.length === 0) {
    const empty = document.createElement("div");
    empty.className = "cm-transcript-preview-empty";
    empty.textContent = buildFallbackPreview(text, status, previewText, progress);
    target.replaceChildren(empty);
    return;
  }
  renderTranscriptRows(target, rows, { showHeader: true });
}

function normalizeLevel(level: number): number {
  if (!Number.isFinite(level) || level <= 0) return 0;
  if (level <= 1) return level;
  return Math.min(1, level / 100);
}

function formatProgress(progress?: TranscriptDownloadProgress): string | null {
  if (!progress) return null;
  if (progress.stage === "Installing") {
    return "Downloaded · installing...";
  }
  if (progress.stage === "Preparing") {
    return "Downloaded · preparing engine...";
  }
  const percent = Math.min(100, Math.max(0, progress.fractionCompleted * 100));
  if (progress.totalBytes <= 0) {
    if (progress.receivedBytes > 0) {
      const receivedMb = (progress.receivedBytes / (1024 * 1024)).toFixed(1);
      return `${receivedMb} MB`;
    }
    return `${percent.toFixed(0)}%`;
  }
  if (progress.totalBytes < 1024 * 1024) {
    return `${percent.toFixed(0)}%`;
  }
  const receivedMb = (progress.receivedBytes / (1024 * 1024)).toFixed(1);
  const totalMb = (progress.totalBytes / (1024 * 1024)).toFixed(1);
  return `${percent.toFixed(0)}% · ${receivedMb}/${totalMb} MB`;
}

function formatMeterDb(level: number): string {
  if (level <= 0.001) return "-60 dB";
  return `${Math.round(20 * Math.log10(level))} dB`;
}

function formatBytes(bytes?: number): string | null {
  if (!bytes || bytes <= 0) return null;
  const mb = bytes / (1024 * 1024);
  if (mb < 1024) {
    return `${Math.round(mb)} MB`;
  }
  return `${(mb / 1024).toFixed(1)} GB`;
}

function preferredEnabledDevice(
  devices: TranscriptDeviceOption[],
  fallbackValue: string,
): TranscriptDeviceOption | undefined {
  return (
    devices.find((device) => device.value === fallbackValue) ??
    devices.find((device) => device.value !== "off" && device.active) ??
    devices.find((device) => device.value !== "off" && device.value !== "default" && device.value !== "all") ??
    devices.find((device) => device.value !== "off")
  );
}

function makeMeter(
  label: string,
  sublabel: string,
  value: number,
  peak: number,
  tone: "mic" | "system",
): HTMLElement {
  const segmentCount = 28;
  const litCount = Math.round(normalizeLevel(value) * segmentCount);
  const peakIndex = Math.max(0, Math.min(segmentCount - 1, Math.round(normalizeLevel(peak) * segmentCount) - 1));
  const warnStart = Math.round(segmentCount * 0.75);
  const clipStart = Math.round(segmentCount * 0.92);
  const wrap = document.createElement("div");
  wrap.className = "cm-transcript-meter";
  wrap.dataset.tone = tone;

  const titleWrap = document.createElement("div");
  titleWrap.className = "cm-transcript-meter-title";

  const title = document.createElement("div");
  title.className = "cm-transcript-meter-label";
  title.textContent = label;

  const subtitle = document.createElement("div");
  subtitle.className = "cm-transcript-meter-subtitle";
  subtitle.textContent = sublabel;

  const valueEl = document.createElement("span");
  valueEl.className = "cm-transcript-meter-value";
  valueEl.textContent = formatMeterDb(normalizeLevel(peak));

  const bar = document.createElement("div");
  bar.className = "cm-transcript-meter-bar";
  for (let index = 0; index < segmentCount; index += 1) {
    const segment = document.createElement("div");
    segment.className = "cm-transcript-meter-segment";
    if (index < litCount) {
      segment.classList.add("cm-transcript-meter-segment--active");
    }
    if (index >= warnStart) {
      segment.classList.add("cm-transcript-meter-segment--warn");
    }
    if (index >= clipStart) {
      segment.classList.add("cm-transcript-meter-segment--clip");
    }
    if (index === peakIndex) {
      segment.classList.add("cm-transcript-meter-segment--peak");
    }
    bar.appendChild(segment);
  }

  titleWrap.appendChild(title);
  titleWrap.appendChild(subtitle);
  wrap.appendChild(titleWrap);
  wrap.appendChild(bar);
  wrap.appendChild(valueEl);
  return wrap;
}

function buildTranscriptGlyph(kind: "model" | "mic" | "system" | "close"): SVGSVGElement {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  svg.classList.add("cm-transcript-settings-glyph");

  if (kind === "close") {
    svg.setAttribute("fill", "none");
    svg.setAttribute("stroke", "currentColor");
    svg.setAttribute("stroke-width", "1.8");
    svg.setAttribute("stroke-linecap", "round");
    const pathA = document.createElementNS("http://www.w3.org/2000/svg", "path");
    const pathB = document.createElementNS("http://www.w3.org/2000/svg", "path");
    pathA.setAttribute("d", "M6 6l12 12");
    pathB.setAttribute("d", "M18 6 6 18");
    svg.append(pathA, pathB);
    return svg;
  }

  svg.setAttribute("fill", "none");
  svg.setAttribute("stroke", "currentColor");
  svg.setAttribute("stroke-width", "1.8");
  svg.setAttribute("stroke-linecap", "round");
  svg.setAttribute("stroke-linejoin", "round");

  const paths: string[] = [];
  if (kind === "model") {
    paths.push("M12 3 4 7v10l8 4 8-4V7l-8-4Z");
    paths.push("M12 12 20 7");
    paths.push("M12 12 4 7");
    paths.push("M12 21V12");
  } else if (kind === "mic") {
    paths.push("M9 4a3 3 0 0 1 6 0v5a3 3 0 0 1-6 0V4Z");
    paths.push("M5 10a7 7 0 0 0 14 0");
    paths.push("M12 17v3");
  } else {
    paths.push("M11 5 6 9H3v6h3l5 4V5Z");
    paths.push("M15.5 8.5a4 4 0 0 1 0 7");
    paths.push("M18.5 5.5a8 8 0 0 1 0 13");
  }

  for (const d of paths) {
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", d);
    svg.appendChild(path);
  }
  return svg;
}

function buildCaretGlyph(): HTMLSpanElement {
  const caret = document.createElement("span");
  caret.className = "cm-transcript-settings-caret";
  caret.textContent = "▾";
  return caret;
}

function makeSettingsMeter(value: number, peak: number, tone: "mic" | "system"): HTMLElement {
  const meter = makeMeter("", "", value, peak, tone);
  meter.classList.add("cm-transcript-settings-meter");
  meter.querySelector(".cm-transcript-meter-title")?.remove();
  const valueEl = meter.querySelector(".cm-transcript-meter-value");
  if (valueEl) {
    valueEl.className = "cm-transcript-settings-meter-value";
  }
  const bar = meter.querySelector(".cm-transcript-meter-bar");
  if (bar) {
    bar.classList.add("cm-transcript-settings-meter-bar");
  }
  meter.querySelectorAll(".cm-transcript-meter-segment").forEach((segment) => {
    segment.classList.add("cm-transcript-settings-meter-segment");
  });
  return meter;
}

function updateMeterElement(
  meter: HTMLElement,
  label: string,
  sublabel: string,
  value: number,
  peak: number,
): void {
  meter.querySelector<HTMLElement>(".cm-transcript-meter-label")?.replaceChildren(document.createTextNode(label));
  meter.querySelector<HTMLElement>(".cm-transcript-meter-subtitle")?.replaceChildren(document.createTextNode(sublabel));
  const normalizedValue = normalizeLevel(value);
  const normalizedPeak = normalizeLevel(peak);
  const segmentCount = 28;
  const litCount = Math.round(normalizedValue * segmentCount);
  const peakIndex = Math.max(0, Math.min(segmentCount - 1, Math.round(normalizedPeak * segmentCount) - 1));
  meter
    .querySelector<HTMLElement>(".cm-transcript-meter-value, .cm-transcript-settings-meter-value")
    ?.replaceChildren(document.createTextNode(formatMeterDb(normalizedPeak)));
  const segments = meter.querySelectorAll<HTMLElement>(".cm-transcript-meter-segment");
  segments.forEach((segment, index) => {
    segment.classList.toggle("cm-transcript-meter-segment--active", index < litCount);
    segment.classList.toggle("cm-transcript-meter-segment--peak", index === peakIndex);
  });
}

export function createTranscriptWidget(
  snapshot: TranscriptWidgetSnapshot,
  applyRuntimePatch: (range: TranscriptBlockRange, patch: TranscriptWidgetRuntimePatch) => void,
  applyUiPatch: (range: TranscriptBlockRange, patch: TranscriptWidgetUiPatch) => void,
  requestMeasure: () => void,
): HTMLElement {
  let currentRange = { ...snapshot.range };
  let currentModelLabel = snapshot.modelLabel;
  let currentModelValue = snapshot.currentModelValue;
  let currentModelMetadata = snapshot.modelMetadata ? { ...snapshot.modelMetadata } : undefined;
  let currentModels = snapshot.models.map((model) => ({ ...model }));
  let currentPreviewText = snapshot.previewText;
  let currentMic = { ...snapshot.micDevice };
  let currentSystem = { ...snapshot.systemDevice };
  let lastEnabledMic = snapshot.micDevice.value !== "off" ? { ...snapshot.micDevice } : undefined;
  let lastEnabledSystem = snapshot.systemDevice.value !== "off" ? { ...snapshot.systemDevice } : undefined;
  let currentMicDevices = snapshot.micDevices.map((device) => ({ ...device }));
  let currentSystemDevices = snapshot.systemDevices.map((device) => ({ ...device }));
  let currentStatus: TranscriptStatus = snapshot.status;
  let currentMicLevel = snapshot.micLevel;
  let currentSystemLevel = snapshot.systemLevel;
  let currentMicPeak = snapshot.micLevel;
  let currentSystemPeak = snapshot.systemLevel;
  let currentProgress = snapshot.downloadProgress ? { ...snapshot.downloadProgress } : undefined;
  let currentError = snapshot.errorMessage ?? "";
  let currentText = snapshot.text;
  let currentLineCount = snapshot.lineCount;
  let currentSettingsPanelOpen = snapshot.settingsPanelOpen;
  let currentMinimized = snapshot.minimized;
  let currentModelDropdownOpen = snapshot.modelDropdownOpen;
  let currentDropdownSource = snapshot.deviceDropdownSource;
  let currentRequestSource = snapshot.deviceRequestSource;
  let lastPreviewSignature = "";
  let lastPreviewLayoutSignature = buildPreviewLayoutSignature(
    snapshot.text,
    snapshot.status,
    snapshot.previewText,
    snapshot.downloadProgress?.stage,
    Boolean(snapshot.errorMessage),
  );
  let lastModalSignature = "";
  let transcriptModalBackdrop: HTMLDivElement | null = null;
  let transcriptModalContent: HTMLDivElement | null = null;
  let transcriptModalAutoFollow = true;
  let transcriptModalProgrammaticScroll = false;
  let currentLevelMonitorSignature = "";
  let currentLevelMonitorRange: TranscriptBlockRange | null = null;

  function updatePeak(previous: number, next: number): number {
    return next >= previous ? next : Math.max(next, previous - 0.08);
  }

  function statusLabelForDisplay(): string {
    if (currentStatus === "Recording") return "Transcribing";
    if (currentStatus === "Processing" && currentProgress) return currentProgress.stage;
    return currentStatus;
  }

  const root = document.createElement("div") as TranscriptWidgetRoot;
  root.dataset.blockFrom = String(currentRange.blockFrom);
  root.dataset.blockTo = String(currentRange.blockTo);

  const header = document.createElement("div");
  header.className = "cm-transcript-header";

  const meta = document.createElement("div");
  meta.className = "cm-transcript-meta";
  const headerActions = document.createElement("div");
  headerActions.className = "cm-transcript-header-actions";
  const status = buildButton("", "Toggle transcribing", () => {
    toggleRecording();
  });
  status.className = "cm-transcript-status";

  header.appendChild(meta);
  header.appendChild(headerActions);
  root.appendChild(header);

  const progress = document.createElement("div");
  progress.className = "cm-transcript-progress";
  root.appendChild(progress);

  const levelRow = document.createElement("div");
  levelRow.className = "cm-transcript-level-row";
  root.appendChild(levelRow);
  const micLevelMeter = makeMeter("Mic", "You", currentMicLevel, currentMicPeak, "mic");
  const systemLevelMeter = makeMeter("System", "Others", currentSystemLevel, currentSystemPeak, "system");
  levelRow.append(micLevelMeter, systemLevelMeter);

  const previewShell = document.createElement("div");
  previewShell.className = "cm-transcript-preview-shell";
  root.appendChild(previewShell);

  const preview = document.createElement("div");
  preview.className = "cm-transcript-preview";
  previewShell.appendChild(preview);
  const minimizedBar = document.createElement("div");
  minimizedBar.className = "cm-transcript-minimized";
  minimizedBar.hidden = true;
  const minimizedToggle = document.createElement("button");
  minimizedToggle.type = "button";
  minimizedToggle.className = "cm-transcript-minimized-toggle";
  const minimizedDot = document.createElement("span");
  minimizedDot.className = "cm-transcript-minimized-dot";
  minimizedToggle.appendChild(minimizedDot);
  const minimizedText = document.createElement("div");
  minimizedText.className = "cm-transcript-minimized-text";
  const minimizedSpeaker = document.createElement("span");
  minimizedSpeaker.className = "cm-transcript-minimized-speaker";
  const minimizedMessage = document.createElement("span");
  minimizedMessage.className = "cm-transcript-minimized-message";
  minimizedText.append(minimizedSpeaker, minimizedMessage);
  const minimizedActions = document.createElement("div");
  minimizedActions.className = "cm-transcript-minimized-actions";
  minimizedBar.append(minimizedToggle, minimizedText, minimizedActions);
  minimizedBar.title = "Expand transcript";
  minimizedBar.setAttribute("aria-label", "Expand transcript");
  minimizedBar.addEventListener("mousedown", suppressTranscriptPress);
  minimizedBar.addEventListener("click", suppressTranscriptPress);
  minimizedBar.addEventListener("pointerdown", (event) => {
    suppressTranscriptPress(event);
    syncMinimizedState(false);
  });
  root.appendChild(minimizedBar);

  const openTranscriptButton = buildIconButton("Open full transcript", "fullscreen", () => {
    if (!transcriptModalBackdrop) return;
    transcriptModalBackdrop.hidden = false;
    transcriptModalAutoFollow = true;
    renderModalTranscript(true);
  });

  transcriptModalBackdrop = document.createElement("div");
  transcriptModalBackdrop.className = "cm-transcript-modal-backdrop";
  transcriptModalBackdrop.hidden = true;
  transcriptModalBackdrop.addEventListener("click", (event) => {
    if (event.target === transcriptModalBackdrop) {
      transcriptModalBackdrop.hidden = true;
    }
  });

  const transcriptModal = document.createElement("div");
  transcriptModal.className = "cm-transcript-modal";
  transcriptModalBackdrop.appendChild(transcriptModal);

  const transcriptModalHeader = document.createElement("div");
  transcriptModalHeader.className = "cm-transcript-modal-header";
  transcriptModal.appendChild(transcriptModalHeader);

  const transcriptModalTitle = document.createElement("div");
  transcriptModalTitle.className = "cm-transcript-modal-title";
  transcriptModalTitle.textContent = "Transcript";
  transcriptModalHeader.appendChild(transcriptModalTitle);

  const closeTranscriptButton = document.createElement("button");
  closeTranscriptButton.type = "button";
  closeTranscriptButton.className = "cm-transcript-modal-close";
  closeTranscriptButton.textContent = "Close";
  closeTranscriptButton.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    transcriptModalBackdrop!.hidden = true;
  });
  transcriptModalHeader.appendChild(closeTranscriptButton);

  transcriptModalContent = document.createElement("div");
  transcriptModalContent.className = "cm-transcript-modal-content";
  transcriptModalContent.addEventListener("scroll", () => {
    if (!transcriptModalContent || transcriptModalProgrammaticScroll) return;
    transcriptModalAutoFollow = isTranscriptModalNearBottom(transcriptModalContent);
  });
  transcriptModal.appendChild(transcriptModalContent);

  document.body.appendChild(transcriptModalBackdrop);

  const error = document.createElement("div");
  error.className = "cm-transcript-error";
  root.appendChild(error);
  const settingsWrap = document.createElement("div");
  settingsWrap.className = "cm-transcript-settings";
  const settingsPanel = document.createElement("div");
  settingsPanel.className = "cm-transcript-settings-panel";
  settingsPanel.hidden = true;
  const settingsPanelHeader = document.createElement("div");
  settingsPanelHeader.className = "cm-transcript-settings-panel-header";
  const settingsPanelTitle = document.createElement("div");
  settingsPanelTitle.className = "cm-transcript-settings-panel-title";
  settingsPanelTitle.textContent = "Transcript settings";
  const settingsCloseButton = document.createElement("button");
  settingsCloseButton.type = "button";
  settingsCloseButton.className = "cm-transcript-settings-close";
  settingsCloseButton.title = "Close transcript settings";
  settingsCloseButton.setAttribute("aria-label", "Close transcript settings");
  settingsCloseButton.appendChild(buildTranscriptGlyph("close"));
  bindTranscriptPress(settingsCloseButton, () => {
    syncModelDropdownState(undefined);
    syncDropdownState(undefined, undefined);
    syncSettingsPanelState(undefined);
  });
  settingsPanelHeader.append(settingsPanelTitle, settingsCloseButton);
  settingsPanel.appendChild(settingsPanelHeader);

  const settingsPanelBody = document.createElement("div");
  settingsPanelBody.className = "cm-transcript-settings-panel-body";
  settingsPanel.appendChild(settingsPanelBody);

  const clearTranscript = () => {
    window.chirami.transcriptClearBlock(currentRange);
    postToSwift({ type: "transcriptRecordClear", range: currentRange });
    currentError = "";
    currentProgress = undefined;
    currentText = "";
    currentLineCount = 0;
    currentMicPeak = 0;
    currentSystemPeak = 0;
    setStatus("Idle");
    refresh();
  };

  const toggleRecording = () => {
    if (currentStatus === "Recording" || currentStatus === "Paused" || currentStatus === "Processing") {
      applyRuntimePatch(currentRange, {
        status: "Processing",
      });
      postToSwift({ type: "transcriptRecordStop", range: currentRange });
      setStatus("Processing");
      return;
    }
    applyRuntimePatch(currentRange, {
      status: "Processing",
      errorMessage: undefined,
      downloadProgress: undefined,
    });
    postToSwift({
      type: "transcriptRecordStart",
      range: currentRange,
      micDevice: currentMic,
      systemDevice: currentSystem,
    });
    setStatus("Processing");
  };
  bindTranscriptPress(minimizedToggle, () => {
    toggleRecording();
  });
  const clearActionButton = buildIconButton("Clear transcript", "clear", () => {
    if (currentStatus === "Processing") return;
    clearTranscript();
  });
  const minimizeActionButton = buildIconButton("Minimize transcript", "minimize", () => {
    syncSettingsPanelState(undefined);
    syncMinimizedState(true);
  });
  const settingsButton = buildIconButton("Transcript settings", "settings", () => {
    const nextOpen = currentSettingsPanelOpen !== true;
    if (!nextOpen) {
      syncModelDropdownState(undefined);
      syncDropdownState(undefined, undefined);
      syncSettingsPanelState(undefined);
      return;
    }
    syncSettingsPanelState(true);
  });
  const expandActionButton = buildIconButton("Restore transcript", "restore", () => {
    syncMinimizedState(false);
  });

  type DeviceDropdown = {
    wrap: HTMLDivElement;
    trigger: HTMLButtonElement;
    toggle: HTMLButtonElement;
    name: HTMLDivElement;
    subtitle: HTMLDivElement;
    detail: HTMLDivElement;
    meter: HTMLDivElement;
    requestHint: HTMLDivElement;
    menu: HTMLDivElement;
  };

  type ModelDropdown = {
    wrap: HTMLDivElement;
    trigger: HTMLButtonElement;
    name: HTMLDivElement;
    detail: HTMLDivElement;
    hint: HTMLDivElement;
    status: HTMLSpanElement;
    menu: HTMLDivElement;
  };

  type DropdownLike = {
    menu: HTMLDivElement;
  };

  function positionFloatingMenu(dropdown: DropdownLike): void {
    void dropdown;
  }

  function positionVisibleMenus(): void {
    return;
  }

  function stopLevelMonitor(): void {
    if (!currentLevelMonitorRange) return;
    postToSwift({ type: "transcriptLevelMonitorStop", range: currentLevelMonitorRange });
    currentLevelMonitorSignature = "";
    currentLevelMonitorRange = null;
  }

  function syncLevelMonitor(): void {
    const micEnabled = currentMic.value !== "off";
    const systemEnabled = currentSystem.value !== "off";
    const shouldMonitor =
      currentSettingsPanelOpen === true &&
      currentStatus !== "Recording" &&
      currentStatus !== "Paused" &&
      currentStatus !== "Processing" &&
      (micEnabled || systemEnabled);

    if (!shouldMonitor) {
      stopLevelMonitor();
      return;
    }

    const signature = JSON.stringify({
      blockFrom: currentRange.blockFrom,
      blockTo: currentRange.blockTo,
      mic: currentMic,
      system: currentSystem,
    });
    if (signature === currentLevelMonitorSignature) return;

    if (currentLevelMonitorRange) {
      postToSwift({ type: "transcriptLevelMonitorStop", range: currentLevelMonitorRange });
    }
    postToSwift({
      type: "transcriptLevelMonitorStart",
      range: currentRange,
      micDevice: currentMic,
      systemDevice: currentSystem,
    });
    currentLevelMonitorSignature = signature;
    currentLevelMonitorRange = { ...currentRange };
  }

  function syncSettingsPanelState(nextOpen?: boolean, patchUi = true): void {
    currentSettingsPanelOpen = nextOpen;
    settingsPanel.hidden = currentSettingsPanelOpen !== true;
    if (currentSettingsPanelOpen !== true) {
      syncModelDropdownState(undefined, false);
      syncDropdownState(undefined, undefined, false);
    }
    syncLevelMonitor();
    if (patchUi) {
      applyUiPatch(currentRange, {
        settingsPanelOpen: currentSettingsPanelOpen,
      });
    }
  }

  function syncMinimizedState(nextMinimized?: boolean, patchUi = true): void {
    if (currentMinimized === nextMinimized) return;
    currentMinimized = nextMinimized;
    if (patchUi) {
      applyUiPatch(currentRange, {
        minimized: currentMinimized,
      });
    }
    refresh();
    requestMeasure();
  }

  function syncModelDropdownState(nextOpen?: boolean, patchUi = true): void {
    currentModelDropdownOpen = nextOpen;
    modelDropdown.menu.hidden = currentModelDropdownOpen !== true;
    modelDropdown.wrap.classList.toggle("cm-transcript-settings-model--open", currentModelDropdownOpen === true);
    if (currentModelDropdownOpen === true) {
      positionFloatingMenu(modelDropdown);
    }
    if (patchUi) {
      applyUiPatch(currentRange, {
        modelDropdownOpen: currentModelDropdownOpen,
      });
    }
  }

  function syncDropdownState(nextSource?: TranscriptSource, nextRequestSource?: TranscriptSource, patchUi = true): void {
    currentDropdownSource = nextSource;
    currentRequestSource = nextRequestSource;
    if (nextSource !== undefined || nextRequestSource !== undefined) {
      syncModelDropdownState(undefined, patchUi);
    }
    micDropdown.menu.hidden = currentDropdownSource !== "mic";
    systemDropdown.menu.hidden = currentDropdownSource !== "system";
    micDropdown.wrap.classList.toggle("cm-transcript-settings-source--open", currentDropdownSource === "mic");
    systemDropdown.wrap.classList.toggle("cm-transcript-settings-source--open", currentDropdownSource === "system");
    if (currentDropdownSource === "mic") {
      positionFloatingMenu(micDropdown);
    } else if (currentDropdownSource === "system") {
      positionFloatingMenu(systemDropdown);
    }
    micDropdown.requestHint.hidden = currentRequestSource !== "mic";
    systemDropdown.requestHint.hidden = currentRequestSource !== "system";
    micDropdown.requestHint.textContent = "Refreshing microphone devices...";
    systemDropdown.requestHint.textContent = "Refreshing system audio devices...";
    if (patchUi) {
      applyUiPatch(currentRange, {
        deviceDropdownSource: currentDropdownSource,
        deviceRequestSource: currentRequestSource,
      });
    }
  }

  function requestDevices(source: TranscriptSource): void {
    syncDropdownState(source, source);
    postToSwift({ type: "transcriptDevicesRequest", range: currentRange, source });
  }

  function requestModelState(): void {
    postToSwift({ type: "transcriptModelRequest", range: currentRange });
  }

  function createSettingsGroup(label: string): HTMLDivElement {
    const wrap = document.createElement("div");
    wrap.className = "cm-transcript-settings-group";
    const title = document.createElement("div");
    title.className = "cm-transcript-settings-group-label";
    title.textContent = label;
    wrap.appendChild(title);
    return wrap;
  }

  function createDeviceDropdown(
    source: TranscriptSource,
    label: string,
    subtitle: string,
    glyph: "mic" | "system",
  ): DeviceDropdown {
    const wrap = document.createElement("div");
    wrap.className = "cm-transcript-settings-source";

    const trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "cm-transcript-settings-card cm-transcript-settings-source-card";
    trigger.title = `${label} device`;
    trigger.setAttribute("aria-label", `${label} device`);
    bindTranscriptPress(trigger, () => {
      const nextOpen = currentDropdownSource !== source;
      if (!nextOpen) {
        syncDropdownState(undefined, undefined);
        return;
      }
      requestDevices(source);
    });

    const iconWrap = document.createElement("div");
    iconWrap.className = "cm-transcript-settings-card-icon";
    iconWrap.appendChild(buildTranscriptGlyph(glyph));

    const toggle = document.createElement("button");
    toggle.type = "button";
    toggle.className = "cm-transcript-source-toggle";
    toggle.title = `${label} source toggle`;
    toggle.setAttribute("aria-label", `${label} source toggle`);
    const toggleThumb = document.createElement("span");
    toggleThumb.className = "cm-transcript-source-toggle-thumb";
    toggle.appendChild(toggleThumb);

    const body = document.createElement("div");
    body.className = "cm-transcript-settings-card-body";

    const titleRow = document.createElement("div");
    titleRow.className = "cm-transcript-settings-card-title-row";

    const name = document.createElement("div");
    name.className = "cm-transcript-settings-card-title";

    const caret = buildCaretGlyph();
    titleRow.append(name, caret);

    const subtitleEl = document.createElement("div");
    subtitleEl.className = "cm-transcript-settings-card-subtitle";
    subtitleEl.textContent = subtitle;

    const detail = document.createElement("div");
    detail.className = "cm-transcript-settings-card-detail";

    const meter = document.createElement("div");
    meter.className = "cm-transcript-settings-card-meter";

    body.append(titleRow, subtitleEl, detail, meter);
    trigger.append(iconWrap, body);
    wrap.appendChild(trigger);
    wrap.appendChild(toggle);

    const requestHint = document.createElement("div");
    requestHint.className = "cm-transcript-device-request";
    requestHint.hidden = true;
    wrap.appendChild(requestHint);

    const menu = document.createElement("div");
    menu.className = "cm-transcript-device-menu";
    menu.hidden = true;
    wrap.appendChild(menu);

    return { wrap, trigger, toggle, name, subtitle: subtitleEl, detail, meter, requestHint, menu };
  }

  const modelGroup = createSettingsGroup("Model");
  const audioGroup = createSettingsGroup("Audio sources");
  const audioSourceList = document.createElement("div");
  audioSourceList.className = "cm-transcript-settings-source-list";
  audioGroup.appendChild(audioSourceList);

  const micDropdown = createDeviceDropdown("mic", "Mic", "Your voice", "mic");
  const systemDropdown = createDeviceDropdown("system", "System", "Everyone else", "system");
  const micSettingsMeter = makeSettingsMeter(currentMicLevel, currentMicPeak, "mic");
  const systemSettingsMeter = makeSettingsMeter(currentSystemLevel, currentSystemPeak, "system");
  micDropdown.meter.appendChild(micSettingsMeter);
  systemDropdown.meter.appendChild(systemSettingsMeter);

  function toggleSourceEnabled(source: TranscriptSource): void {
    const isMic = source === "mic";
    const currentDevice = isMic ? currentMic : currentSystem;
    const currentDevices = isMic ? currentMicDevices : currentSystemDevices;
    const lastEnabledDevice = isMic ? lastEnabledMic : lastEnabledSystem;
    const isEnabled = currentDevice.value !== "off";
    const nextDevice = isEnabled
      ? { value: "off", label: "Off" }
      : lastEnabledDevice ?? preferredEnabledDevice(currentDevices, isMic ? "default" : "all");

    if (!nextDevice) return;

    postToSwift({
      type: "transcriptDeviceSelect",
      range: currentRange,
      source,
      value: nextDevice.value,
      label: nextDevice.label,
    });
    if (isMic) {
      currentMic = { value: nextDevice.value, label: nextDevice.label };
      if (nextDevice.value !== "off") {
        lastEnabledMic = { ...currentMic };
      }
    } else {
      currentSystem = { value: nextDevice.value, label: nextDevice.label };
      if (nextDevice.value !== "off") {
        lastEnabledSystem = { ...currentSystem };
      }
    }
    refresh();
    syncDropdownState(undefined, undefined);
  }

  bindTranscriptPress(micDropdown.toggle, () => {
    toggleSourceEnabled("mic");
  });
  bindTranscriptPress(systemDropdown.toggle, () => {
    toggleSourceEnabled("system");
  });

  function createModelDropdown(label: string): ModelDropdown {
    const wrap = document.createElement("div");
    wrap.className = "cm-transcript-settings-model";

    const trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "cm-transcript-settings-card cm-transcript-settings-model-card";
    trigger.title = `${label} model`;
    trigger.setAttribute("aria-label", `${label} model`);
    bindTranscriptPress(trigger, () => {
      const modelSelectionLocked =
        currentStatus === "Recording" || currentStatus === "Paused" || currentStatus === "Processing";
      if (modelSelectionLocked) return;
      const nextOpen = currentModelDropdownOpen !== true;
      if (!nextOpen) {
        syncModelDropdownState(undefined);
        return;
      }
      syncSettingsPanelState(true);
      syncDropdownState(undefined, undefined);
      syncModelDropdownState(true);
      requestModelState();
    });

    const iconWrap = document.createElement("div");
    iconWrap.className = "cm-transcript-settings-card-icon cm-transcript-settings-card-icon--model";
    iconWrap.appendChild(buildTranscriptGlyph("model"));

    const body = document.createElement("div");
    body.className = "cm-transcript-settings-card-body";

    const titleRow = document.createElement("div");
    titleRow.className = "cm-transcript-settings-card-title-row";
    const name = document.createElement("div");
    name.className = "cm-transcript-settings-card-title";
    const status = document.createElement("span");
    status.className = "cm-transcript-settings-badge";
    titleRow.append(name, status);

    const detail = document.createElement("div");
    detail.className = "cm-transcript-settings-card-detail";

    const hint = document.createElement("div");
    hint.className = "cm-transcript-settings-model-hint";

    body.append(titleRow, detail, hint);
    trigger.append(iconWrap, body, buildCaretGlyph());
    wrap.appendChild(trigger);

    const menu = document.createElement("div");
    menu.className = "cm-transcript-device-menu";
    menu.hidden = true;
    wrap.appendChild(menu);

    return { wrap, trigger, name, detail, hint, status, menu };
  }

  const modelDropdown = createModelDropdown("Model");

  function selectedModelOption(): TranscriptDeviceOption | undefined {
    return currentModels.find((model) => model.value === currentModelValue);
  }

  function selectedDeviceOption(
    source: TranscriptSource,
    selected: TranscriptDeviceSnapshot,
  ): TranscriptDeviceOption | undefined {
    const options = source === "mic" ? currentMicDevices : currentSystemDevices;
    return options.find((device) => device.value === selected.value);
  }

  function renderDropdownMenu(
    dropdown: DeviceDropdown,
    source: TranscriptSource,
    selected: TranscriptDeviceSnapshot,
    devices: TranscriptDeviceOption[],
  ): void {
    dropdown.menu.replaceChildren();
    const visibleDevices = devices.filter((device) => device.value !== "off");

    for (const device of visibleDevices) {
      dropdown.menu.appendChild(
        buildSelectItem(device.label, device.detail ?? device.value, () => {
          postToSwift({
            type: "transcriptDeviceSelect",
            range: currentRange,
            source,
            value: device.value,
            label: device.label,
          });
          if (source === "mic") {
            currentMic = { value: device.value, label: device.label };
            if (device.value !== "off") {
              lastEnabledMic = { ...currentMic };
            }
          } else {
            currentSystem = { value: device.value, label: device.label };
            if (device.value !== "off") {
              lastEnabledSystem = { ...currentSystem };
            }
          }
          refresh();
          syncDropdownState(undefined, undefined);
        }, selected.value === device.value),
      );
    }
  }

  function renderDeviceMenus(): void {
    renderDropdownMenu(micDropdown, "mic", currentMic, currentMicDevices);
    renderDropdownMenu(systemDropdown, "system", currentSystem, currentSystemDevices);
  }

  function renderModelMenu(): void {
    modelDropdown.menu.replaceChildren();
    for (const model of currentModels) {
      modelDropdown.menu.appendChild(
        buildSelectItem(model.label, model.detail ?? model.value, () => {
          postToSwift({
            type: "transcriptModelSelect",
            range: currentRange,
            value: model.value,
          });
          currentModelValue = model.value;
          currentModelLabel = model.label;
          refresh();
          syncModelDropdownState(undefined);
        }, currentModelValue === model.value),
      );
    }
  }

  renderDeviceMenus();
  renderModelMenu();
  syncSettingsPanelState(currentSettingsPanelOpen, false);
  syncMinimizedState(currentMinimized, false);
  syncModelDropdownState(currentModelDropdownOpen, false);
  syncDropdownState(currentDropdownSource, currentRequestSource, false);

  headerActions.appendChild(status);
  headerActions.appendChild(clearActionButton);
  headerActions.appendChild(settingsWrap);
  headerActions.appendChild(minimizeActionButton);
  headerActions.appendChild(openTranscriptButton);
  settingsWrap.appendChild(settingsButton);
  settingsPanelBody.appendChild(modelGroup);
  settingsPanelBody.appendChild(audioGroup);
  modelGroup.appendChild(modelDropdown.wrap);
  audioSourceList.append(micDropdown.wrap, systemDropdown.wrap);
  settingsWrap.appendChild(settingsPanel);

  function setStatus(next: TranscriptStatus): void {
    currentStatus = next;
    refresh();
  }

  function isTranscriptModalNearBottom(target: HTMLElement): boolean {
    return target.scrollHeight - target.clientHeight - target.scrollTop <= transcriptModalAutoFollowThresholdPx;
  }

  function setTranscriptModalScrollTop(target: HTMLElement, nextTop: number): void {
    transcriptModalProgrammaticScroll = true;
    target.scrollTop = nextTop;
    window.requestAnimationFrame(() => {
      transcriptModalProgrammaticScroll = false;
      if (transcriptModalContent === target) {
        transcriptModalAutoFollow = isTranscriptModalNearBottom(target);
      }
    });
  }

  function renderModalTranscript(forceFollow = false): void {
    if (!transcriptModalContent || !transcriptModalBackdrop || transcriptModalBackdrop.hidden) return;
    const modalSignature = JSON.stringify({
      text: currentText,
      previewText: currentPreviewText,
      status: currentStatus,
      progressStage: currentProgress?.stage,
      error: currentError,
    });
    if (!forceFollow && modalSignature === lastModalSignature) {
      return;
    }
    lastModalSignature = modalSignature;
    const previousScrollTop = transcriptModalContent.scrollTop;
    const wasNearBottom = isTranscriptModalNearBottom(transcriptModalContent);
    const shouldFollow = forceFollow || (transcriptModalAutoFollow && wasNearBottom);
    renderTranscriptModalContent(
      transcriptModalContent,
      currentText,
      currentStatus,
      currentPreviewText,
      currentProgress,
    );
    const nextTop = shouldFollow
      ? transcriptModalContent.scrollHeight
      : Math.min(previousScrollTop, Math.max(0, transcriptModalContent.scrollHeight - transcriptModalContent.clientHeight));
    setTranscriptModalScrollTop(transcriptModalContent, nextTop);
  }

  function renderPreview(force = false): void {
    const previewSignature = JSON.stringify({
      text: currentText,
      previewText: currentPreviewText,
      status: currentStatus,
      progressStage: currentProgress?.stage,
    });
    if (!force && previewSignature === lastPreviewSignature) {
      return;
    }
    lastPreviewSignature = previewSignature;
    const previewRows = buildTranscriptPreviewRows(currentText, currentStatus, currentPreviewText);
    preview.replaceChildren();
    if (previewRows.length === 0) {
      const empty = document.createElement("div");
      empty.className = "cm-transcript-preview-empty";
      empty.textContent = buildFallbackPreview(currentText, currentStatus, currentPreviewText, currentProgress);
      preview.appendChild(empty);
    } else {
      const visiblePreviewRows = previewRows.slice(-transcriptPreviewVisibleRowCount);
      renderTranscriptRows(preview, visiblePreviewRows, {
        compact: true,
        padToCount: transcriptPreviewVisibleRowCount,
        showHeader: false,
      });
    }
  }

  function refresh(): void {
    root.className = `cm-transcript-container cm-transcript-status-${currentStatus.toLowerCase()}${currentMinimized === true ? " cm-transcript-container--minimized" : ""}`;
    currentMicPeak = updatePeak(currentMicPeak, normalizeLevel(currentMicLevel));
    currentSystemPeak = updatePeak(currentSystemPeak, normalizeLevel(currentSystemLevel));
    const micEnabled = currentMic.value !== "off";
    const systemEnabled = currentSystem.value !== "off";
    const hasEnabledSource = micEnabled || systemEnabled;
    const isProcessing = currentStatus === "Processing";
    const isRecordingActive = currentStatus === "Recording" || currentStatus === "Paused";
    const canStart = currentStatus === "Idle" || currentStatus === "Completed" || currentStatus === "Error";
    const canStartRecording = canStart && hasEnabledSource;
    status.className = `cm-transcript-status cm-transcript-status--${currentStatus.toLowerCase()}`;
    status.textContent = isRecordingActive ? "Transcribing" : canStart ? "Transcribe" : statusLabelForDisplay();
    status.title = isRecordingActive
      ? "Stop transcribing"
      : canStartRecording
        ? "Begin transcribing"
        : canStart
          ? "Enable at least one audio source"
          : "Processing transcript...";
    status.disabled = isProcessing || (canStart && !canStartRecording);
    meta.textContent = `${currentLineCount} line${currentLineCount === 1 ? "" : "s"}`;
    renderPreview();
    updateMeterElement(micLevelMeter, "Mic", micEnabled ? "You" : "Disabled", micEnabled ? currentMicLevel : 0, micEnabled ? currentMicPeak : 0);
    updateMeterElement(systemLevelMeter, "System", systemEnabled ? "Others" : "Disabled", systemEnabled ? currentSystemLevel : 0, systemEnabled ? currentSystemPeak : 0);
    const progressText = formatProgress(currentProgress);
    progress.textContent = progressText ? `Model download: ${progressText}` : "";
    error.textContent = currentError ? currentError : "";
    error.hidden = currentMinimized === true || !currentError;
    const previewRows = buildTranscriptPreviewRows(currentText, currentStatus, currentPreviewText);
    const hasTranscript = previewRows.length > 0 || Boolean(currentPreviewText?.trim());
    openTranscriptButton.disabled = !hasTranscript;
    renderModalTranscript();
    header.hidden = currentMinimized === true;
    progress.hidden = currentMinimized === true || progressText === null;
    levelRow.hidden = currentMinimized === true;
    previewShell.hidden = currentMinimized === true;
    minimizedBar.hidden = currentMinimized !== true;

    clearActionButton.disabled = isProcessing;
    minimizeActionButton.disabled = currentMinimized === true;
    const modelSelectionLocked = currentStatus === "Recording" || currentStatus === "Paused" || currentStatus === "Processing";

    settingsButton.className = currentSettingsPanelOpen === true
      ? "cm-transcript-icon-button cm-transcript-button--active"
      : "cm-transcript-icon-button";
    modelDropdown.trigger.classList.toggle("cm-transcript-settings-card--active", currentModelDropdownOpen === true);
    const modelOption = selectedModelOption();
    const modelProgressText = formatProgress(currentProgress);
    const installedSizeLabel = formatBytes(currentModelMetadata?.installedSizeBytes);
    const kindLabel = currentModelMetadata?.kindLabel ?? "On-device";
    const configuredLanguage = currentModelMetadata?.configuredLanguage?.trim() || "auto";
    const supportedLanguages = currentModelMetadata?.supportedLanguages?.join(", ");
    modelDropdown.name.textContent = modelOption?.label ?? currentModelLabel;
    modelDropdown.detail.textContent = [
      kindLabel,
      installedSizeLabel,
      "on-device",
    ].filter(Boolean).join(" · ") || "On-device speech model";
    modelDropdown.hint.textContent = modelProgressText
      ? `Model download: ${modelProgressText}`
      : [
          currentModelMetadata?.installed ? "Downloaded" : "Not downloaded",
          supportedLanguages,
          `Configured: ${configuredLanguage}`,
        ].filter(Boolean).join(" · ");
    modelDropdown.status.textContent = modelProgressText ? currentProgress?.stage ?? "Working" : "Active";
    modelDropdown.status.className = modelProgressText
      ? "cm-transcript-settings-badge cm-transcript-settings-badge--progress"
      : "cm-transcript-settings-badge";
    modelDropdown.trigger.disabled = modelSelectionLocked;
    const micOption = selectedDeviceOption("mic", currentMic);
    const systemOption = selectedDeviceOption("system", currentSystem);
    micDropdown.trigger.classList.toggle("cm-transcript-settings-card--active", currentDropdownSource === "mic");
    micDropdown.toggle.classList.toggle("cm-transcript-source-toggle--on", micEnabled);
    micDropdown.toggle.title = micEnabled ? "Disable microphone capture" : "Enable microphone capture";
    micDropdown.name.textContent = currentMic.label;
    micDropdown.subtitle.textContent = micEnabled ? "Your voice" : "Disabled";
    micDropdown.detail.textContent = micEnabled
      ? (micOption?.detail ?? "Input source for your voice")
      : "No microphone audio will be captured";
    updateMeterElement(micSettingsMeter, "", "", micEnabled ? currentMicLevel : 0, micEnabled ? currentMicPeak : 0);
    systemDropdown.trigger.classList.toggle("cm-transcript-settings-card--active", currentDropdownSource === "system");
    systemDropdown.toggle.classList.toggle("cm-transcript-source-toggle--on", systemEnabled);
    systemDropdown.toggle.title = systemEnabled ? "Disable system audio capture" : "Enable system audio capture";
    systemDropdown.name.textContent = currentSystem.label;
    systemDropdown.subtitle.textContent = systemEnabled ? "Everyone else" : "Disabled";
    systemDropdown.detail.textContent = systemOption?.detail ?? (!systemEnabled
      ? "No system audio will be captured"
      : "Capture app and meeting audio");
    updateMeterElement(systemSettingsMeter, "", "", systemEnabled ? currentSystemLevel : 0, systemEnabled ? currentSystemPeak : 0);
    const latestRow = latestTranscriptRow(previewRows);
    const latestSpeaker = latestRow?.speaker?.trim() ?? "";
    const latestText = latestRow?.text?.trim() || buildFallbackPreview(currentText, currentStatus, currentPreviewText, currentProgress).replace(/\s+/g, " ").trim();
    minimizedDot.className = `cm-transcript-minimized-dot cm-transcript-minimized-dot--${currentStatus.toLowerCase()}`;
    minimizedToggle.disabled = isProcessing || (canStart && !canStartRecording);
    minimizedToggle.title = isRecordingActive
      ? "Stop transcribing"
      : canStartRecording
        ? "Begin transcribing"
        : canStart
          ? "Enable at least one audio source"
          : "Processing transcript...";
    minimizedToggle.setAttribute("aria-label", minimizedToggle.title);
    minimizedSpeaker.textContent = latestSpeaker;
    minimizedSpeaker.hidden = latestSpeaker.length === 0 || latestSpeaker.toLowerCase() === "live";
    minimizedSpeaker.className = "cm-transcript-minimized-speaker";
    if (latestSpeaker.toLowerCase() === "you") {
      minimizedSpeaker.classList.add("cm-transcript-minimized-speaker--self");
    }
    minimizedMessage.textContent = latestText;
    settingsButton.className = currentSettingsPanelOpen === true
      ? "cm-transcript-icon-button cm-transcript-button--active"
      : "cm-transcript-icon-button";
    if (currentMinimized === true) {
      minimizedActions.replaceChildren(settingsWrap, expandActionButton);
    } else {
      headerActions.replaceChildren(status, clearActionButton, settingsWrap, minimizeActionButton, openTranscriptButton);
      minimizedActions.replaceChildren();
    }
    positionVisibleMenus();
    syncLevelMonitor();
  }

  root.__chiramiTranscriptApplySnapshot = (nextSnapshot) => {
    const previousLayoutSignature = lastPreviewLayoutSignature;
    currentRange = { ...nextSnapshot.range };
    currentModelLabel = nextSnapshot.modelLabel;
    currentModelValue = nextSnapshot.currentModelValue;
    currentModelMetadata = nextSnapshot.modelMetadata ? { ...nextSnapshot.modelMetadata } : undefined;
    currentModels = nextSnapshot.models.map((model) => ({ ...model }));
    currentPreviewText = nextSnapshot.previewText;
    currentMic = { ...nextSnapshot.micDevice };
    currentSystem = { ...nextSnapshot.systemDevice };
    if (currentMic.value !== "off") {
      lastEnabledMic = { ...currentMic };
    }
    if (currentSystem.value !== "off") {
      lastEnabledSystem = { ...currentSystem };
    }
    currentMicDevices = nextSnapshot.micDevices.map((device) => ({ ...device }));
    currentSystemDevices = nextSnapshot.systemDevices.map((device) => ({ ...device }));
    currentStatus = nextSnapshot.status;
    currentMicLevel = nextSnapshot.micLevel;
    currentSystemLevel = nextSnapshot.systemLevel;
    currentMicPeak = updatePeak(currentMicPeak, normalizeLevel(nextSnapshot.micLevel));
    currentSystemPeak = updatePeak(currentSystemPeak, normalizeLevel(nextSnapshot.systemLevel));
    currentProgress = nextSnapshot.downloadProgress ? { ...nextSnapshot.downloadProgress } : undefined;
    currentError = nextSnapshot.errorMessage ?? "";
    currentText = nextSnapshot.text;
    currentLineCount = nextSnapshot.lineCount;
    root.dataset.blockFrom = String(currentRange.blockFrom);
    root.dataset.blockTo = String(currentRange.blockTo);
    renderModelMenu();
    renderDeviceMenus();
    syncSettingsPanelState(nextSnapshot.settingsPanelOpen, false);
    syncMinimizedState(nextSnapshot.minimized, false);
    syncModelDropdownState(nextSnapshot.modelDropdownOpen, false);
    syncDropdownState(nextSnapshot.deviceDropdownSource, nextSnapshot.deviceRequestSource, false);
    lastPreviewLayoutSignature = buildPreviewLayoutSignature(
      currentText,
      currentStatus,
      currentPreviewText,
      currentProgress?.stage,
      Boolean(currentError),
    );
    refresh();
    if (previousLayoutSignature !== lastPreviewLayoutSignature) {
      requestMeasure();
    }
  };
  root.__chiramiTranscriptRequestMeasure = requestMeasure;
  root.__chiramiTranscriptCleanup = () => {
    stopLevelMonitor();
    transcriptModalBackdrop?.remove();
    modelDropdown.menu.remove();
    micDropdown.menu.remove();
    systemDropdown.menu.remove();
  };

  refresh();
  requestModelState();

  return root;
}
