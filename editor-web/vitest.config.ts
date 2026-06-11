import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Pure-logic tests only: run in plain Node, no jsdom.
    environment: "node",
    include: ["src/**/*.test.ts"],
    setupFiles: ["src/test/setup.ts"],
  },
});
