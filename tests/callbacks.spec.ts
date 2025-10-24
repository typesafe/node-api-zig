import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("callback parameters", () => {
  const capturedValue = 3;

  it("support closures as expected", () => {
    expect(
      addon.functions.fnCallback(123, (foo: number) => {
        return foo * capturedValue;
      })
    ).toEqual(369);
  });

  it("should propagate thrown errors", () => {
    expect(() => {
      addon.functions.fnCallback(123, () => {
        throw new Error("Kablooie");
      });
    }).toThrowError("Kablooie");
  });

  it.skip("TODO: should be callable from async functions", async () => {
    expect(
      await addon.functions.fnCallbackAsync((foo) => {
        console.log("CALLED FROM ZIG", foo);
        return foo * 5;
      })
    ).toEqual("ok");
  });
});
