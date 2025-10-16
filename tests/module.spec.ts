import addon from "sample";
import { describe, it, expect } from "bun:test";
import { gc } from "bun";

describe("Import Node-API module", () => {
  const c = new addon.C(12);
  it("should return module value", () => {
    console.log("CLASS ", addon.C);

    console.log("instance ", c);
    console.log("c.foo = ", c.foo);
    c.foo = 1000;
    console.log("callMe = ", c.callMe(13, "tralala"));

    expect(addon).toBeDefined();
  });

  it("should pass params by ref", () => {
    console.log("callWithParamsByRef", c.callWithParamsByRef(1456, "bar", ["foo"]));
  });
});

describe("Finalizer", () => {
  it("should call deinit", () => {
    // no reference to newed obj
    new addon.C(12);
    gc(true);
  });
});
