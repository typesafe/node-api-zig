import addon from "sample";
import { describe, it, expect } from "bun:test";
import { gc } from "bun";

describe("Import Node-API module", () => {
  it("should return module value", () => {
    console.log("CLASS ", addon.C);
    const c = new addon.C(12);

    console.log("instance ", c);
    console.log("c.foo = ", c.foo);
    c.foo = 1000;
    console.log("callMe = ", c.callMe(13, "tralala"));

    expect(addon).toBeDefined();
  });
});

describe("Finalizer", () => {
  it("should call deinit", () => {
    // no reference to newed obj
    new addon.C(12);
    gc(true);
  });
});
