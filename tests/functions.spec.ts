import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("defineFunction", () => {
  it("should define function", () => {
    expect(addon.functions.fnWithSerializedParams).toBeFunction();
  });

  it("should fail when called with missing arguments", () => {
    expect(() => addon.functions.fnWithSerializedParams(123)).toThrow(
      "MissingArguments"
    );
  });

  it("should fail when called with argument of different type", () => {
    expect(() => addon.functions.fnWithSerializedParams(123, "foo")).toThrow(
      "BooleanExpected"
    );
  });

  describe("with pointer to native class instanciated in JS", () => {
    it("should unwrap the instance", () => {
      const i = new addon.TestClass(123);
      expect(addon.functions.fnWithJsNewedNativeInstance(i)).toBe(i);
    });
  });

  describe("with allocator parameter", () => {
    it("should serialize params and return values", () => {
      expect(addon.functions.fnWithAllocatorParam(42)).toEqual(
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
      );
    });
  });

  describe("with callback parameter", () => {
    it("should call callback", () => {
      expect(
        addon.functions.fnCallback((foo) => {
          console.log("CALLED FROM ZIG", foo);
          return foo * 3;
        })
      ).toEqual("ok");
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
