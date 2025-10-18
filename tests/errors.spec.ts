import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("Import Node-API module", () => {
  it("should return module value", () => {
    expect(addon).toBeDefined();
  });
});
