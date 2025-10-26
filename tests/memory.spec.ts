import { describe, it, expect } from "bun:test";
import { gc, sleep } from "bun";

import requireTestModule from "./zig_modules";
const addon = requireTestModule("test-module");

// this will be GC'ed (and finalized)
new addon.TestClass(12);

describe("struct.deinit", () => {
  it("should call deinit", async () => {
    const count = addon.TestClass.getInstanceCount();
    expect(count).toBeGreaterThan(0); // other tests can influence this

    gc(true);

    // give finalizers a chance to kick in (works for Bun, not sure about other runtimes)
    await sleep(0);

    expect(addon.TestClass.getInstanceCount()).toEqual(count - 1n);
  });
});
