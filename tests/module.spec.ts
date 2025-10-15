import addon from "sample";
import { describe, it, expect } from "bun:test";

describe("Import Node-API module", () => {
  it("should return module value", () => {
    console.log("CLASS ", addon.C);
    const c = new addon.C();
    console.log("instance ", c);
    c.callMe(12);

    expect(addon).toBeDefined();
  });
});
