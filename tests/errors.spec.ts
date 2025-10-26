import { describe, it, expect } from "bun:test";

import requireTestModule from "./zig_modules";
const addon = requireTestModule("test-module");

describe("Import Node-API module", () => {
  it("should return module value", () => {
    expect(addon).toBeDefined();
  });
});
