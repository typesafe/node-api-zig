import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("Import Zig Node-API module", () => {
  it("should return Zig struct instance with all exported members", () => {
    expect(addon).toBeDefined();
    expect(addon.TestClass).toBeFunction();

    console.log(addon);
  });
});
