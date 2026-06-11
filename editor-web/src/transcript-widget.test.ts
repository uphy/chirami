import { describe, expect, it } from "vitest";
import { buildTranscriptPreviewRows, sameTranscriptWidgetSnapshot, TranscriptWidgetSnapshot } from "./transcript-widget";

const line1 = "[2026-06-11 10:00:00] You: hello";
const line2 = "[2026-06-11 10:00:10] Others: hi there";

describe("buildTranscriptPreviewRows", () => {
  it("returns no rows for empty text", () => {
    expect(buildTranscriptPreviewRows("", "Idle")).toEqual([]);
  });

  it("parses committed lines into time/speaker/text rows and marks the last as latest", () => {
    const rows = buildTranscriptPreviewRows(`${line1}\n${line2}\n`, "Completed");
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ time: "10:00:00", speaker: "You", text: "hello" });
    expect(rows[0]!.latest).toBeUndefined();
    expect(rows[1]).toMatchObject({ time: "10:00:10", speaker: "Others", text: "hi there", latest: true });
  });

  it("keeps unparseable lines as plain text rows", () => {
    const rows = buildTranscriptPreviewRows("free-form note", "Completed");
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ time: "", speaker: "", text: "free-form note", latest: true });
  });

  it("drops blank lines and trailing whitespace", () => {
    const rows = buildTranscriptPreviewRows(`${line1}   \n\n   \n${line2}\n`, "Completed");
    expect(rows).toHaveLength(2);
    expect(rows[0]!.text).toBe("hello");
  });

  it("appends a provisional Live row while recording with preview text", () => {
    const rows = buildTranscriptPreviewRows(`${line1}\n`, "Recording", "typing...");
    expect(rows).toHaveLength(2);
    expect(rows[0]!.latest).toBeUndefined();
    expect(rows[1]).toMatchObject({
      time: "",
      speaker: "Live",
      text: "typing...",
      provisional: true,
      latest: true,
    });
  });

  it("ignores preview text when not recording", () => {
    const rows = buildTranscriptPreviewRows(`${line1}\n`, "Completed", "leftover preview");
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ text: "hello", latest: true });
  });

  it("ignores blank preview text while recording", () => {
    const rows = buildTranscriptPreviewRows(`${line1}\n`, "Recording", "   ");
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ text: "hello", latest: true });
  });
});

describe("sameTranscriptWidgetSnapshot", () => {
  function snapshot(overrides: Partial<TranscriptWidgetSnapshot> = {}): TranscriptWidgetSnapshot {
    return {
      range: { blockFrom: 0, blockTo: 10 },
      text: "",
      lineCount: 0,
      status: "Idle",
      modelLabel: "Configured model",
      modelValue: "",
      models: [],
      micDevice: { value: "default", label: "Default" },
      systemDevice: { value: "all", label: "All System Audio" },
      micLevel: 0,
      systemLevel: 0,
      micDevices: [],
      systemDevices: [],
      devicesRevision: 0,
      ...overrides,
    };
  }

  it("treats structurally equal snapshots as the same", () => {
    expect(sameTranscriptWidgetSnapshot(snapshot(), snapshot())).toBe(true);
  });

  it("detects scalar differences", () => {
    expect(sameTranscriptWidgetSnapshot(snapshot(), snapshot({ status: "Recording" }))).toBe(false);
  });

  it("compares nested objects structurally", () => {
    const left = snapshot({ micDevice: { value: "mic-1", label: "Mic" } });
    const right = snapshot({ micDevice: { value: "mic-1", label: "Mic" } });
    expect(sameTranscriptWidgetSnapshot(left, right)).toBe(true);
    expect(
      sameTranscriptWidgetSnapshot(left, snapshot({ micDevice: { value: "mic-2", label: "Mic" } })),
    ).toBe(false);
  });
});
