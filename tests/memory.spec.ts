import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";
import { gc } from "bun";

describe("Finalizer", () => {
  it("should call deinit", () => {
    // no reference to newed obj
    new addon.TestClass(12);
    gc(true);
  });
});
