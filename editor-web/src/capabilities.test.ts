import { beforeEach, describe, expect, it } from "vitest";
import { applyCapabilities, hasCapability } from "./capabilities";

describe("capabilities", () => {
  beforeEach(() => {
    // Module state is shared within this file; restore the all-enabled default.
    applyCapabilities({ transcript: true, pasteImage: true, fold: true });
  });

  it("defaults to all capabilities enabled", () => {
    expect(hasCapability("transcript")).toBe(true);
    expect(hasCapability("pasteImage")).toBe(true);
    expect(hasCapability("fold")).toBe(true);
  });

  it("applies a partial update without touching other capabilities", () => {
    applyCapabilities({ transcript: false });
    expect(hasCapability("transcript")).toBe(false);
    expect(hasCapability("pasteImage")).toBe(true);
    expect(hasCapability("fold")).toBe(true);
  });

  it("merges successive partial updates", () => {
    applyCapabilities({ transcript: false });
    applyCapabilities({ fold: false });
    expect(hasCapability("transcript")).toBe(false);
    expect(hasCapability("pasteImage")).toBe(true);
    expect(hasCapability("fold")).toBe(false);
  });
});
