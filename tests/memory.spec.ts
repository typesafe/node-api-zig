import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";
import { gc, sleep } from "bun";

new addon.TestClass(12);
const count = addon.TestClass.getInstanceCount();

describe("struct.deinit", () => {
  it("should call deinit", async () => {
    expect(count).toEqual(1n);
    gc(true);
    // give finalizers a chance to kick in
    await sleep(0);
    expect(addon.TestClass.getInstanceCount()).toEqual(count - 1n);
  });
});
