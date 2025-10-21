import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("defineFunction with callback", () => {
  it("should call callback", () => {
    expect(
      addon.functions.fnCallback((foo) => {
        console.log("CALLED FROM ZIG", foo);
        return foo * 3;
      })
    ).toEqual("ok");
  });

  it("should propagate errors thrown in callback", () => {
    expect(() => {
      addon.functions.fnCallback(() => {
        throw new Error("Kablooie");
      });
    }).toThrowError("Kablooie");
  });
});

describe("defineAsyncFunction with callback", () => {
  it("should call callback", async () => {
    expect(
      await addon.functions.fnCallbackAsync((foo) => {
        console.log("CALLED FROM ZIG", foo);
        return foo * 5;
      })
    ).toEqual("ok");
  });
});
