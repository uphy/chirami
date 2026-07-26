import { beforeEach, describe, expect, it } from "vitest";
import { applyCapabilities, hasCapability } from "./capabilities";

describe("capabilities", () => {
  beforeEach(() => {
    // Module state is shared within this file; restore the all-enabled default.
    applyCapabilities({ pasteImage: true, fold: true });
  });

  it("defaults to all capabilities enabled", () => {
    expect(hasCapability("pasteImage")).toBe(true);
    expect(hasCapability("fold")).toBe(true);
  });

  it("applies a partial update without touching other capabilities", () => {
    applyCapabilities({ pasteImage: false });
    expect(hasCapability("pasteImage")).toBe(false);
    expect(hasCapability("fold")).toBe(true);
  });

  it("merges successive partial updates", () => {
    applyCapabilities({ pasteImage: false });
    applyCapabilities({ fold: false });
    expect(hasCapability("pasteImage")).toBe(false);
    expect(hasCapability("fold")).toBe(false);
  });
});
