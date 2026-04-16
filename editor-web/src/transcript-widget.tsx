import { postToSwift } from "./bridge";
import type {
  TranscriptBlockRange,
  TranscriptDeviceOption,
  TranscriptDeviceSnapshot,
  TranscriptDownloadProgress,
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
  const suppress = (event: Event) => {
    event.preventDefault();
    event.stopPropagation();
  };
  button.addEventListener("pointerdown", suppress);
  button.addEventListener("mousedown", suppress);
  button.addEventListener("click", suppress);
  button.addEventListener("pointerup", suppress);
  button.addEventListener("mouseup", suppress);
  button.addEventListener("pointerdown", (event) => {
    suppress(event);
    onClick();
  });
  return button;
}

function buildIconButton(title: string, onClick: () => void): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "cm-transcript-icon-button";
  button.title = title;
  button.setAttribute("aria-label", title);
  const suppress = (event: Event) => {
    event.preventDefault();
    event.stopPropagation();
  };
  button.addEventListener("pointerdown", suppress);
  button.addEventListener("mousedown", suppress);
  button.addEventListener("click", suppress);
  button.addEventListener("pointerup", suppress);
  button.addEventListener("mouseup", suppress);
  button.addEventListener("pointerdown", (event) => {
    suppress(event);
    onClick();
  });

  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  svg.classList.add("cm-transcript-icon-button-svg");

  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  path.setAttribute(
    "d",
    "M19.14 12.94c.04-.31.06-.63.06-.94s-.02-.63-.06-.94l2.03-1.58a.5.5 0 0 0 .12-.64l-1.92-3.32a.5.5 0 0 0-.6-.22l-2.39.96a7.1 7.1 0 0 0-1.63-.94l-.36-2.54a.5.5 0 0 0-.5-.42h-3.84a.5.5 0 0 0-.5.42l-.36 2.54c-.58.22-1.12.53-1.63.94l-2.39-.96a.5.5 0 0 0-.6.22L2.7 8.84a.5.5 0 0 0 .12.64l2.03 1.58c-.04.31-.06.63-.06.94s.02.63.06.94L2.82 14.52a.5.5 0 0 0-.12.64l1.92 3.32a.5.5 0 0 0 .6.22l2.39-.96c.5.4 1.05.72 1.63.94l.36 2.54a.5.5 0 0 0 .5.42h3.84a.5.5 0 0 0 .5-.42l.36-2.54c.58-.22 1.13-.54 1.63-.94l2.39.96a.5.5 0 0 0 .6-.22l1.92-3.32a.5.5 0 0 0-.12-.64l-2.03-1.58ZM12 15.5A3.5 3.5 0 1 1 12 8.5a3.5 3.5 0 0 1 0 7Z",
  );
  path.setAttribute("fill", "currentColor");
  svg.appendChild(path);
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
  const suppress = (event: Event) => {
    event.preventDefault();
    event.stopPropagation();
  };
  button.addEventListener("pointerdown", (event) => {
    suppress(event);
    onClick();
  });
  button.addEventListener("mousedown", suppress);
  button.addEventListener("click", suppress);
  button.addEventListener("pointerup", suppress);
  button.addEventListener("mouseup", suppress);
  button.addEventListener("keydown", (event) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    suppress(event);
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
    visibleRowCount: Math.min(rows.length, transcriptPreviewVisibleRowCount),
    hasMoreTranscript: rows.length > transcriptPreviewVisibleRowCount,
    status,
    progressStage: progressStage ?? "",
    hasError,
  });
}

type RenderTranscriptRowsOptions = {
  compact?: boolean;
  padToCount?: number;
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

  const headerRow = document.createElement("div");
  headerRow.className = "cm-transcript-preview-row cm-transcript-preview-row--header";
  for (const label of ["Time", "Speaker", "Text"]) {
    const cell = document.createElement("div");
    cell.className = "cm-transcript-preview-cell";
    cell.textContent = label;
    headerRow.appendChild(cell);
  }
  table.appendChild(headerRow);

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
  renderTranscriptRows(target, rows);
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

export function createTranscriptWidget(
  snapshot: TranscriptWidgetSnapshot,
  applyRuntimePatch: (range: TranscriptBlockRange, patch: TranscriptWidgetRuntimePatch) => void,
  applyUiPatch: (range: TranscriptBlockRange, patch: TranscriptWidgetUiPatch) => void,
  requestMeasure: () => void,
): HTMLElement {
  let currentRange = { ...snapshot.range };
  let currentModelLabel = snapshot.modelLabel;
  let currentModelValue = snapshot.currentModelValue;
  let currentModels = snapshot.models.map((model) => ({ ...model }));
  let currentPreviewText = snapshot.previewText;
  let currentMic = { ...snapshot.micDevice };
  let currentSystem = { ...snapshot.systemDevice };
  let currentMicDevices = snapshot.micDevices.map((device) => ({ ...device }));
  let currentSystemDevices = snapshot.systemDevices.map((device) => ({ ...device }));
  let currentStatus: TranscriptStatus = snapshot.status;
  let currentMicLevel = snapshot.micLevel;
  let currentSystemLevel = snapshot.systemLevel;
  let currentProgress = snapshot.downloadProgress ? { ...snapshot.downloadProgress } : undefined;
  let currentError = snapshot.errorMessage ?? "";
  let currentText = snapshot.text;
  let currentLineCount = snapshot.lineCount;
  let currentSettingsPanelOpen = snapshot.settingsPanelOpen;
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
  let transcriptModalBackdrop: HTMLDivElement | null = null;
  let transcriptModalContent: HTMLDivElement | null = null;

  const root = document.createElement("div") as TranscriptWidgetRoot;
  root.dataset.blockFrom = String(currentRange.blockFrom);
  root.dataset.blockTo = String(currentRange.blockTo);

  const header = document.createElement("div");
  header.className = "cm-transcript-header";

  const badge = document.createElement("div");
  badge.className = "cm-transcript-badge";
  badge.textContent = "Transcript";

  const status = document.createElement("div");
  status.className = "cm-transcript-status";

  const meta = document.createElement("div");
  meta.className = "cm-transcript-meta";
  const headerActions = document.createElement("div");
  headerActions.className = "cm-transcript-header-actions";

  header.appendChild(badge);
  header.appendChild(status);
  header.appendChild(meta);
  header.appendChild(headerActions);
  root.appendChild(header);

  const progress = document.createElement("div");
  progress.className = "cm-transcript-progress";
  root.appendChild(progress);

  const levelRow = document.createElement("div");
  levelRow.className = "cm-transcript-level-row";
  root.appendChild(levelRow);

  const previewShell = document.createElement("div");
  previewShell.className = "cm-transcript-preview-shell";
  root.appendChild(previewShell);

  const preview = document.createElement("div");
  preview.className = "cm-transcript-preview";
  previewShell.appendChild(preview);

  const openTranscriptButton = document.createElement("button");
  openTranscriptButton.type = "button";
  openTranscriptButton.className = "cm-transcript-jump";
  openTranscriptButton.textContent = "Open full transcript";
  openTranscriptButton.setAttribute("aria-label", "Open full transcript");
  openTranscriptButton.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    event.stopPropagation();
    if (!transcriptModalBackdrop) return;
    if (transcriptModalContent) {
      renderTranscriptModalContent(
        transcriptModalContent,
        currentText,
        currentStatus,
        currentPreviewText,
        currentProgress,
      );
    }
    transcriptModalBackdrop.hidden = false;
  });
  previewShell.appendChild(openTranscriptButton);

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
  transcriptModal.appendChild(transcriptModalContent);

  document.body.appendChild(transcriptModalBackdrop);

  const error = document.createElement("div");
  error.className = "cm-transcript-error";
  root.appendChild(error);

  const controls = document.createElement("div");
  controls.className = "cm-transcript-controls";
  const settingsWrap = document.createElement("div");
  settingsWrap.className = "cm-transcript-settings";
  const settingsPanel = document.createElement("div");
  settingsPanel.className = "cm-transcript-settings-panel";
  settingsPanel.hidden = true;

  const recordButton = buildButton("Start", "Begin recording", () => {
    if (currentStatus === "Recording" || currentStatus === "Paused" || currentStatus === "Processing") {
      postToSwift({ type: "transcriptRecordStop", range: currentRange });
      setStatus("Processing");
      return;
    }
    postToSwift({
      type: "transcriptRecordStart",
      range: currentRange,
      micDevice: currentMic,
      systemDevice: currentSystem,
    });
    setStatus("Processing");
  }, "primary");
  const clearButton = buildButton("Clear", "Clear the transcript block", () => {
    window.chirami.transcriptClearBlock(currentRange);
    postToSwift({ type: "transcriptRecordClear", range: currentRange });
    currentError = "";
    currentProgress = undefined;
    currentText = "";
    currentLineCount = 0;
    setStatus("Idle");
    refresh();
  });
  const settingsButton = buildIconButton("Transcript settings", () => {
    const nextOpen = currentSettingsPanelOpen !== true;
    if (!nextOpen) {
      syncModelDropdownState(undefined);
      syncDropdownState(undefined, undefined);
      syncSettingsPanelState(undefined);
      return;
    }
    syncSettingsPanelState(true);
  });

  const deviceControls = document.createElement("div");
  deviceControls.className = "cm-transcript-device-controls";

  type DeviceDropdown = {
    wrap: HTMLDivElement;
    trigger: HTMLButtonElement;
    requestHint: HTMLDivElement;
    menu: HTMLDivElement;
  };

  type ModelDropdown = {
    wrap: HTMLDivElement;
    trigger: HTMLButtonElement;
    menu: HTMLDivElement;
  };

  type DropdownLike = {
    trigger: HTMLButtonElement;
    menu: HTMLDivElement;
  };

  function positionFloatingMenu(dropdown: DropdownLike): void {
    const { trigger, menu } = dropdown;
    if (menu.hidden) return;

    const triggerRect = trigger.getBoundingClientRect();
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;
    const horizontalMargin = 12;
    const verticalGap = 6;
    const width = Math.min(
      Math.max(triggerRect.width, 240),
      Math.max(240, viewportWidth - horizontalMargin * 2),
    );
    const maxHeight = 260;

    menu.style.position = "fixed";
    menu.style.width = `${width}px`;
    menu.style.left = `${Math.min(
      Math.max(horizontalMargin, triggerRect.left),
      Math.max(horizontalMargin, viewportWidth - width - horizontalMargin),
    )}px`;

    const estimatedHeight = Math.min(maxHeight, Math.max(menu.scrollHeight, 80));
    const spaceBelow = viewportHeight - triggerRect.bottom - horizontalMargin;
    const shouldOpenUpward = spaceBelow < estimatedHeight + verticalGap && triggerRect.top > spaceBelow;
    menu.style.top = shouldOpenUpward
      ? `${Math.max(horizontalMargin, triggerRect.top - estimatedHeight - verticalGap)}px`
      : `${Math.min(viewportHeight - horizontalMargin - estimatedHeight, triggerRect.bottom + verticalGap)}px`;
    menu.style.maxHeight = `${maxHeight}px`;
  }

  function positionVisibleMenus(): void {
    positionFloatingMenu(modelDropdown);
    positionFloatingMenu(micDropdown);
    positionFloatingMenu(systemDropdown);
  }

  function syncSettingsPanelState(nextOpen?: boolean, patchUi = true): void {
    currentSettingsPanelOpen = nextOpen;
    settingsPanel.hidden = currentSettingsPanelOpen !== true;
    if (currentSettingsPanelOpen !== true) {
      syncModelDropdownState(undefined, false);
      syncDropdownState(undefined, undefined, false);
    }
    if (patchUi) {
      applyUiPatch(currentRange, {
        settingsPanelOpen: currentSettingsPanelOpen,
      });
    }
  }

  function syncModelDropdownState(nextOpen?: boolean, patchUi = true): void {
    currentModelDropdownOpen = nextOpen;
    modelDropdown.menu.hidden = currentModelDropdownOpen !== true;
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

  function createDeviceDropdown(source: TranscriptSource, label: string): DeviceDropdown {
    const wrap = document.createElement("div");
    wrap.className = "cm-transcript-device-dropdown";

    const title = document.createElement("div");
    title.className = "cm-transcript-device-dropdown-label";
    title.textContent = label;
    wrap.appendChild(title);

    const trigger = buildButton("", `${label} device`, () => {
      const nextOpen = currentDropdownSource !== source;
      if (!nextOpen) {
        syncDropdownState(undefined, undefined);
        return;
      }
      requestDevices(source);
    });
    trigger.className = "cm-transcript-select-trigger";
    wrap.appendChild(trigger);

    const requestHint = document.createElement("div");
    requestHint.className = "cm-transcript-device-request";
    requestHint.hidden = true;
    wrap.appendChild(requestHint);

    const menu = document.createElement("div");
    menu.className = "cm-transcript-device-menu";
    menu.hidden = true;
    document.body.appendChild(menu);

    return { wrap, trigger, requestHint, menu };
  }

  const micDropdown = createDeviceDropdown("mic", "Mic");
  const systemDropdown = createDeviceDropdown("system", "System");

  function createModelDropdown(label: string): ModelDropdown {
    const wrap = document.createElement("div");
    wrap.className = "cm-transcript-device-dropdown";

    const title = document.createElement("div");
    title.className = "cm-transcript-device-dropdown-label";
    title.textContent = label;
    wrap.appendChild(title);

    const trigger = buildButton("", `${label} model`, () => {
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
    trigger.className = "cm-transcript-select-trigger";
    wrap.appendChild(trigger);

    const menu = document.createElement("div");
    menu.className = "cm-transcript-device-menu";
    menu.hidden = true;
    document.body.appendChild(menu);

    return { wrap, trigger, menu };
  }

  const modelDropdown = createModelDropdown("Model");

  function renderDropdownMenu(
    dropdown: DeviceDropdown,
    source: TranscriptSource,
    selected: TranscriptDeviceSnapshot,
    devices: TranscriptDeviceOption[],
  ): void {
    dropdown.menu.replaceChildren();

    for (const device of devices) {
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
          } else {
            currentSystem = { value: device.value, label: device.label };
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
  syncModelDropdownState(currentModelDropdownOpen, false);
  syncDropdownState(currentDropdownSource, currentRequestSource, false);

  controls.appendChild(recordButton);
  controls.appendChild(clearButton);
  headerActions.appendChild(settingsWrap);
  settingsWrap.appendChild(settingsButton);
  settingsPanel.appendChild(modelDropdown.wrap);
  deviceControls.appendChild(micDropdown.wrap);
  deviceControls.appendChild(systemDropdown.wrap);
  settingsPanel.appendChild(deviceControls);
  settingsWrap.appendChild(settingsPanel);
  root.appendChild(controls);

  function setStatus(next: TranscriptStatus): void {
    currentStatus = next;
    refresh();
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
      });
    }
  }

  function refresh(): void {
    root.className = `cm-transcript-container cm-transcript-status-${currentStatus.toLowerCase()}`;
    status.textContent = currentStatus === "Processing" && currentProgress
      ? currentProgress.stage
      : currentStatus;
    meta.textContent = `${currentLineCount} line${currentLineCount === 1 ? "" : "s"}`;
    renderPreview();
    levelRow.replaceChildren(makeMeter("Mic", currentMicLevel), makeMeter("System", currentSystemLevel));
    const progressText = formatProgress(currentProgress);
    progress.textContent = progressText ? `Model download: ${progressText}` : "";
    error.textContent = currentError ? currentError : "";
    error.hidden = !currentError;
    const previewRows = buildTranscriptPreviewRows(currentText, currentStatus, currentPreviewText);
    const hasMoreTranscript = previewRows.length > transcriptPreviewVisibleRowCount;
    openTranscriptButton.classList.toggle(
      "cm-transcript-jump--visible",
      hasMoreTranscript,
    );

    const recordingActive = currentStatus === "Recording" || currentStatus === "Paused" || currentStatus === "Processing";
    recordButton.textContent = recordingActive ? "Stop" : "Start";
    recordButton.title = recordingActive ? "Stop recording" : "Begin recording";
    recordButton.className = recordingActive
      ? "cm-transcript-button cm-transcript-button--danger"
      : "cm-transcript-button cm-transcript-button--primary";
    recordButton.disabled = false;
    clearButton.disabled = currentStatus === "Processing";
    const modelSelectionLocked = currentStatus === "Recording" || currentStatus === "Paused" || currentStatus === "Processing";

    settingsButton.className = currentSettingsPanelOpen === true
      ? "cm-transcript-icon-button cm-transcript-button--active"
      : "cm-transcript-icon-button";
    modelDropdown.trigger.textContent =
      currentModels.find((model) => model.value === currentModelValue)?.label ?? currentModelLabel;
    modelDropdown.trigger.disabled = modelSelectionLocked;
    micDropdown.trigger.textContent = currentMic.label;
    systemDropdown.trigger.textContent = currentSystem.label;
    positionVisibleMenus();
  }

  root.__chiramiTranscriptApplySnapshot = (nextSnapshot) => {
    const previousLayoutSignature = lastPreviewLayoutSignature;
    currentRange = { ...nextSnapshot.range };
    currentModelLabel = nextSnapshot.modelLabel;
    currentModelValue = nextSnapshot.currentModelValue;
    currentModels = nextSnapshot.models.map((model) => ({ ...model }));
    currentPreviewText = nextSnapshot.previewText;
    currentMic = { ...nextSnapshot.micDevice };
    currentSystem = { ...nextSnapshot.systemDevice };
    currentMicDevices = nextSnapshot.micDevices.map((device) => ({ ...device }));
    currentSystemDevices = nextSnapshot.systemDevices.map((device) => ({ ...device }));
    currentStatus = nextSnapshot.status;
    currentMicLevel = nextSnapshot.micLevel;
    currentSystemLevel = nextSnapshot.systemLevel;
    currentProgress = nextSnapshot.downloadProgress ? { ...nextSnapshot.downloadProgress } : undefined;
    currentError = nextSnapshot.errorMessage ?? "";
    currentText = nextSnapshot.text;
    currentLineCount = nextSnapshot.lineCount;
    root.dataset.blockFrom = String(currentRange.blockFrom);
    root.dataset.blockTo = String(currentRange.blockTo);
    renderModelMenu();
    renderDeviceMenus();
    syncSettingsPanelState(nextSnapshot.settingsPanelOpen, false);
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
    transcriptModalBackdrop?.remove();
    modelDropdown.menu.remove();
    micDropdown.menu.remove();
    systemDropdown.menu.remove();
  };

  refresh();
  requestModelState();

  return root;
}
