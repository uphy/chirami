import { markdown } from "@codemirror/lang-markdown";
import { EditorState } from "@codemirror/state";
import { describe, expect, it } from "vitest";
import type { TranscriptChunkPayload } from "../bridge";
import {
  collectTranscriptBlocks,
  insertTranscriptLineInOrder,
  parseTranscriptLineTimestampSeconds,
} from "./transcript";

function seconds(date: string, time: string): number {
  const [year, month, day] = date.split("-").map((part) => Number.parseInt(part, 10));
  const [hour, minute, second] = time.split(":").map((part) => Number.parseInt(part, 10));
  return new Date(year!, month! - 1, day!, hour!, minute!, second!).getTime() / 1000;
}

function chunk(timestamp: number, text: string): TranscriptChunkPayload {
  return { range: { blockFrom: 0, blockTo: 0 }, source: "mic", timestamp, text };
}

describe("parseTranscriptLineTimestampSeconds", () => {
  it("parses a valid transcript line into epoch seconds (local time)", () => {
    const line = "[2026-06-11 10:30:05] You: hello";
    expect(parseTranscriptLineTimestampSeconds(line)).toBe(seconds("2026-06-11", "10:30:05"));
  });

  it("returns null for a line without a timestamp", () => {
    expect(parseTranscriptLineTimestampSeconds("You: hello")).toBeNull();
  });

  it("returns null when no whitespace follows the bracket", () => {
    expect(parseTranscriptLineTimestampSeconds("[2026-06-11 10:30:05]hello")).toBeNull();
  });

  it("returns null for a malformed timestamp", () => {
    expect(parseTranscriptLineTimestampSeconds("[2026-6-11 10:30:05] You: hi")).toBeNull();
  });
});

describe("insertTranscriptLineInOrder", () => {
  const line1 = "[2026-06-11 10:00:00] You: first";
  const line2 = "[2026-06-11 10:00:10] Others: second";
  const line3 = "[2026-06-11 10:00:20] You: third";

  it("starts a new transcript when the text is empty", () => {
    const result = insertTranscriptLineInOrder("", chunk(seconds("2026-06-11", "10:00:00"), line1));
    expect(result).toBe(`${line1}\n`);
  });

  it("appends the newest line at the end", () => {
    const raw = `${line1}\n${line2}\n`;
    const result = insertTranscriptLineInOrder(raw, chunk(seconds("2026-06-11", "10:00:20"), line3));
    expect(result).toBe(`${line1}\n${line2}\n${line3}\n`);
  });

  it("inserts a line before the first newer timestamp", () => {
    const raw = `${line1}\n${line3}\n`;
    const result = insertTranscriptLineInOrder(raw, chunk(seconds("2026-06-11", "10:00:10"), line2));
    expect(result).toBe(`${line1}\n${line2}\n${line3}\n`);
  });

  it("inserts an older line at the beginning", () => {
    const raw = `${line2}\n${line3}\n`;
    const result = insertTranscriptLineInOrder(raw, chunk(seconds("2026-06-11", "10:00:00"), line1));
    expect(result).toBe(`${line1}\n${line2}\n${line3}\n`);
  });

  it("keeps a chunk with an equal timestamp after the existing line", () => {
    const raw = `${line1}\n`;
    const other = "[2026-06-11 10:00:00] Others: same time";
    const result = insertTranscriptLineInOrder(raw, chunk(seconds("2026-06-11", "10:00:00"), other));
    expect(result).toBe(`${line1}\n${other}\n`);
  });

  it("skips non-timestamped lines when finding the insert position", () => {
    const raw = `---\n${line1}\nnote without timestamp\n${line3}\n`;
    const result = insertTranscriptLineInOrder(raw, chunk(seconds("2026-06-11", "10:00:10"), line2));
    expect(result).toBe(`---\n${line1}\nnote without timestamp\n${line2}\n${line3}\n`);
  });

  it("adds a separating newline when appending to text without a trailing newline", () => {
    const result = insertTranscriptLineInOrder(line1, chunk(seconds("2026-06-11", "10:00:10"), line2));
    expect(result).toBe(`${line1}\n${line2}\n`);
  });

  it("trims trailing whitespace from the inserted chunk", () => {
    const result = insertTranscriptLineInOrder("", chunk(seconds("2026-06-11", "10:00:00"), `${line1}   \n`));
    expect(result).toBe(`${line1}\n`);
  });
});

describe("collectTranscriptBlocks", () => {
  function stateOf(doc: string): EditorState {
    return EditorState.create({ doc, extensions: [markdown()] });
  }

  it("collects a transcript fenced code block", () => {
    const body = "[2026-06-11 10:00:00] You: hello\n[2026-06-11 10:00:10] Others: hi";
    const doc = `# Title\n\n\`\`\`transcript\n${body}\n\`\`\`\n`;
    const blocks = collectTranscriptBlocks(stateOf(doc));
    expect(blocks).toHaveLength(1);
    const block = blocks[0]!;
    expect(block.text).toBe(body);
    expect(block.lineCount).toBe(2);
    expect(doc.slice(block.blockFrom, block.blockTo)).toBe(`\`\`\`transcript\n${body}\n\`\`\``);
    expect(doc.slice(block.codeFrom, block.codeTo).trimEnd()).toBe(body);
  });

  it("ignores fenced code blocks of other languages", () => {
    const doc = "```js\nconsole.log(1);\n```\n";
    expect(collectTranscriptBlocks(stateOf(doc))).toHaveLength(0);
  });

  it("matches the language case-insensitively and ignores info options", () => {
    const doc = "```Transcript width=300\n[2026-06-11 10:00:00] You: hi\n```\n";
    expect(collectTranscriptBlocks(stateOf(doc))).toHaveLength(1);
  });

  it("returns an empty-text block for an empty transcript block", () => {
    const doc = "```transcript\n```\n";
    const blocks = collectTranscriptBlocks(stateOf(doc));
    expect(blocks).toHaveLength(1);
    expect(blocks[0]!.text).toBe("");
    expect(blocks[0]!.lineCount).toBe(0);
  });

  it("collects multiple transcript blocks in document order", () => {
    const doc = "```transcript\n[2026-06-11 10:00:00] You: a\n```\n\ntext\n\n```transcript\n[2026-06-11 11:00:00] You: b\n```\n";
    const blocks = collectTranscriptBlocks(stateOf(doc));
    expect(blocks).toHaveLength(2);
    expect(blocks[0]!.blockFrom).toBeLessThan(blocks[1]!.blockFrom);
    expect(blocks[0]!.text).toContain("You: a");
    expect(blocks[1]!.text).toContain("You: b");
  });
});
