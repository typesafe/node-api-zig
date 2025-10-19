import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("defineFunction", () => {
  it("should define function", () => {
    expect(addon.functions.fnWithSerializedParams).toBeFunction();
  });

  describe("with allocator parameter", () => {
    it("should serialize params and return values", () => {
      expect(addon.functions.fnWithAllocatorParam(42)).toEqual(
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
      );
    });
  });

  describe("calling with too few arguments", () => {
    it("should serialize params and return values", () => {
      expect(addon.functions.fnWithAllocatorParam(42)).toEqual(
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
      );
    });
  });
  describe("with native parameters", () => {
    it("should serialize params and return values", () => {
      expect(addon.functions.fnWithSerializedParams(123, true)).toEqual(456);
    });
  });

  describe("with native parameters", () => {
    it("should serialize params and return values", () => {
      expect(addon.functions.fnWithSerializedParams(123, true)).toEqual(456);
    });
  });
});

describe("defineAsyncFunction", () => {
  it("should return Promise", async () => {
    const res = await addon.functions.asyncFunction(200);
    expect(res).toEqual(456);
  });
});
