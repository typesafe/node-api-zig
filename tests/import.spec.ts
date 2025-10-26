import { describe, it, expect } from "bun:test";

import requireTestModule from "./zig_modules";
const addon = requireTestModule("test-module");

describe("Import Zig Node-API module", () => {
  it("should return Zig struct instance with all exported members", () => {
    expect(addon).toBeDefined();
    expect(addon.TestClass).toBeFunction();

    console.log(addon);
  });
});
