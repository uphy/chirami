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
  devicePopoverOpen: boolean;
  deviceRequestSource?: TranscriptSource;
}

export interface TranscriptWidgetRuntimePatch {
  micDevice?: TranscriptDeviceSnapshot;
  systemDevice?: TranscriptDeviceSnapshot;
}

export interface TranscriptWidgetUiPatch {
  devicePopoverOpen?: boolean;
  deviceRequestSource?: TranscriptSource;
}

export interface TranscriptWidgetRoot extends HTMLElement {
  __chiramiTranscriptApplySnapshot?: (snapshot: TranscriptWidgetSnapshot) => void;
  __chiramiTranscriptRequestMeasure?: () => void;
}

function normalizeLines(text: string): string[] {
  return text
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter((line) => line.trim().length > 0);
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

function buildDevicePopover(
  snapshot: TranscriptWidgetSnapshot,
  onSelect: (source: TranscriptSource, value: string, label: string) => void,
): HTMLElement {
  const content = document.createElement("div");

  const title = document.createElement("div");
  title.className = "cm-transcript-device-popover-title";
  title.textContent = "Devices";
  content.appendChild(title);

  const micHeading = document.createElement("div");
  micHeading.className = "cm-transcript-device-heading";
  micHeading.textContent = "Microphone";
  content.appendChild(micHeading);

  content.appendChild(
    buildSelectItem("Default", snapshot.micDevice.label, () => {
      onSelect("mic", "default", "Default");
    }, snapshot.micDevice.value === "default"),
  );

  content.appendChild(
    buildSelectItem("Request devices", "Ask native layer for available microphones", () => {
      onSelect("mic", "__request__", "Request devices");
    }),
  );

  for (const device of snapshot.micDevices) {
    content.appendChild(
      buildSelectItem(device.label, device.detail ?? device.value, () => {
        onSelect("mic", device.value, device.label);
      }, snapshot.micDevice.value === device.value),
    );
  }

  const systemHeading = document.createElement("div");
  systemHeading.className = "cm-transcript-device-heading";
  systemHeading.textContent = "System audio";
  content.appendChild(systemHeading);

  content.appendChild(
    buildSelectItem("Auto", snapshot.systemDevice.label, () => {
      onSelect("system", "auto", "Auto");
    }, snapshot.systemDevice.value === "auto"),
  );

  content.appendChild(
    buildSelectItem("Off", "Do not capture system audio", () => {
      onSelect("system", "off", "Off");
    }, snapshot.systemDevice.value === "off"),
  );

  content.appendChild(
    buildSelectItem("Request devices", "Ask native layer for available audio processes", () => {
      onSelect("system", "__request__", "Request devices");
    }),
  );

  for (const device of snapshot.systemDevices) {
    content.appendChild(
      buildSelectItem(device.label, device.detail ?? device.value, () => {
        onSelect("system", device.value, device.label);
      }, snapshot.systemDevice.value === device.value),
    );
  }

  return content;
}

function buildPreview(text: string, status: TranscriptStatus, previewText?: string): string {
  const lines = normalizeLines(text);
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
        return "Finalizing transcript...";
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

function normalizeLevel(level: number): number {
  if (!Number.isFinite(level) || level <= 0) return 0;
  if (level <= 1) return level;
  return Math.min(1, level / 100);
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
  let popoverOpen = snapshot.devicePopoverOpen;
  let currentRequestSource = snapshot.deviceRequestSource;

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

  header.appendChild(badge);
  header.appendChild(status);
  header.appendChild(meta);
  root.appendChild(header);

  const progress = document.createElement("div");
  progress.className = "cm-transcript-progress";
  root.appendChild(progress);

  const levelRow = document.createElement("div");
  levelRow.className = "cm-transcript-level-row";
  root.appendChild(levelRow);

  const deviceSummary = document.createElement("div");
  deviceSummary.className = "cm-transcript-device-summary";
  root.appendChild(deviceSummary);

  const preview = document.createElement("pre");
  preview.className = "cm-transcript-preview";
  root.appendChild(preview);

  const error = document.createElement("div");
  error.className = "cm-transcript-error";
  root.appendChild(error);

  const controls = document.createElement("div");
  controls.className = "cm-transcript-controls";

  const startButton = buildButton("Start", "Begin recording", () => {
    postToSwift({
      type: "transcriptRecordStart",
      range: currentRange,
      micDevice: currentMic,
      systemDevice: currentSystem,
    });
    setStatus("Recording");
  }, "primary");
  const pauseButton = buildButton("Pause", "Pause recording", () => {
    postToSwift({ type: "transcriptRecordPause", range: currentRange });
    setStatus("Paused");
  });
  const resumeButton = buildButton("Resume", "Resume recording", () => {
    postToSwift({ type: "transcriptRecordResume", range: currentRange });
    setStatus("Recording");
  });
  const stopButton = buildButton("Stop", "Finalize the transcript", () => {
    postToSwift({ type: "transcriptRecordStop", range: currentRange });
    setStatus("Processing");
    window.setTimeout(() => setStatus("Completed"), 250);
  }, "danger");
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

  const deviceWrap = document.createElement("div");
  deviceWrap.className = "cm-transcript-device-wrap";
  const requestHint = document.createElement("div");
  requestHint.className = "cm-transcript-device-request";
  requestHint.hidden = true;
  const popover = document.createElement("div");
  popover.className = "cm-transcript-device-popover";
  function syncPopoverState(nextOpen: boolean, nextRequestSource?: TranscriptSource, patchUi = true): void {
    popoverOpen = nextOpen;
    currentRequestSource = nextRequestSource;
    popover.hidden = !popoverOpen;
    requestHint.hidden = currentRequestSource === undefined;
    requestHint.textContent =
      currentRequestSource === "mic"
        ? "Requesting microphone devices..."
        : currentRequestSource === "system"
          ? "Requesting system audio devices..."
          : "";
    if (patchUi) {
      applyUiPatch(currentRange, {
        devicePopoverOpen: popoverOpen,
        deviceRequestSource: currentRequestSource,
      });
    }
  }
  const deviceButton = buildButton("Devices", "Open device options", () => {
    syncPopoverState(!popoverOpen, undefined);
  });
  deviceWrap.appendChild(deviceButton);
  deviceWrap.appendChild(requestHint);
  popover.hidden = !popoverOpen;
  deviceWrap.appendChild(popover);

  function renderPopover(): void {
    popover.replaceChildren();
    popover.appendChild(
      buildDevicePopover(
        {
          ...snapshot,
          micDevice: currentMic,
          systemDevice: currentSystem,
          micDevices: currentMicDevices,
          systemDevices: currentSystemDevices,
        },
        (source, value, label) => {
          if (value === "__request__") {
            syncPopoverState(true, source);
            postToSwift({ type: "transcriptDevicesRequest", range: currentRange, source });
            return;
          }
          postToSwift({
            type: "transcriptDeviceSelect",
            range: currentRange,
            source,
            value,
            label,
          });
          if (source === "mic") {
            currentMic = { value, label };
          } else {
            currentSystem = { value, label };
          }
          renderPopover();
          refresh();
          syncPopoverState(false, undefined);
        },
      ),
    );
  }
  renderPopover();
  syncPopoverState(popoverOpen, currentRequestSource, false);

  controls.appendChild(startButton);
  controls.appendChild(pauseButton);
  controls.appendChild(resumeButton);
  controls.appendChild(stopButton);
  controls.appendChild(clearButton);
  controls.appendChild(deviceWrap);
  root.appendChild(controls);

  function setStatus(next: TranscriptStatus): void {
    currentStatus = next;
    refresh();
  }

  function refresh(): void {
    root.className = `cm-transcript-container cm-transcript-status-${currentStatus.toLowerCase()}`;
    status.textContent = currentStatus;
    meta.textContent = `${currentLineCount} line${currentLineCount === 1 ? "" : "s"} · ${currentModelLabel}`;
    deviceSummary.textContent = `Mic: ${currentMic.label} · System: ${currentSystem.label}`;
    preview.textContent = buildPreview(currentText, currentStatus, currentPreviewText);
    levelRow.replaceChildren(makeMeter("Mic", currentMicLevel), makeMeter("System", currentSystemLevel));
    const progressText = formatProgress(currentProgress);
    progress.textContent = progressText ? `Model download: ${progressText}` : "";
    error.textContent = currentError ? currentError : "";
    error.hidden = !currentError;

    startButton.disabled = currentStatus === "Recording" || currentStatus === "Processing";
    pauseButton.disabled = currentStatus !== "Recording";
    resumeButton.disabled = currentStatus !== "Paused";
    stopButton.disabled = currentStatus === "Idle" || currentStatus === "Completed";
    clearButton.disabled = currentStatus === "Processing";
  }

  root.__chiramiTranscriptApplySnapshot = (nextSnapshot) => {
    currentRange = { ...nextSnapshot.range };
      currentModelLabel = nextSnapshot.modelLabel;
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
    renderPopover();
    syncPopoverState(nextSnapshot.devicePopoverOpen, nextSnapshot.deviceRequestSource, false);
    refresh();
    requestMeasure();
  };
  root.__chiramiTranscriptRequestMeasure = requestMeasure;

  refresh();

  return root;
}
