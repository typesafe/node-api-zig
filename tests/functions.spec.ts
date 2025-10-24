import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("functions", () => {
  it("should be defined as function", () => {
    expect(addon.functions.fnWithSerializedParams).toBeFunction();
  });

  it("should throw MissingArguments when called with missing arguments", () => {
    expect(() => addon.functions.fnWithSerializedParams(123)).toThrow(
      "MissingArguments"
    );
  });

  it("should throw when called with argument of different type", () => {
    expect(() => addon.functions.fnWithSerializedParams(123, "foo")).toThrow(
      "BooleanExpected"
    );
  });

  describe("with pointer to native class instanciated in JS", () => {
    it("should unwrap the instance", () => {
      const i = new addon.TestClass(123);
      expect(addon.functions.fnWithJsNewedNativeInstance(i)).toBe(i);
      expect(i.foo).toEqual(124);
    });
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
  // describe("with native parameters", () => {
  //   it("calling 1M times", () => {
  //     const start = performance.now();
  //     for (var i = 0; i < 1_000_000; i++) {
  //       addon.functions.fnWithSerializedParams(200);
  //     }
  //     console.log(performance.now() - start);
  //   });
  //   it("calling JS 1M times", () => {
  //     let str = "";
  //     function fn(i, b) {
  //       var res = 0;
  //       var ii = i;
  //       while (i > 0) {
  //         i -= 1;
  //         res += ii * 1.1;
  //       }
  //       return res;
  //     }
  //     const start = performance.now();

  //     for (var i = 0; i < 1_000_000; i++) {
  //       fn(200, true);
  //     }
  //     console.log(performance.now() - start);
  //   });
  // });
});

describe("defineAsyncFunction", () => {
  it("should return Promise", async () => {
    const res = await addon.functions.asyncFunction(200);
    expect(res).toEqual(456);
  });
});
