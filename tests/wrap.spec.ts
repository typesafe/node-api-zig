import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("wrapInstance", () => {
  it("should wrap instance", () => {
    expect(addon.wrappedInstance).toBeObject();
  });
  it("should wrap fields", () => {
    console.log(addon.wrappedInstance);
    expect(addon.wrappedInstance.foo).toEqual(123);
    expect(addon.wrappedInstance.bar).toEqual("hopla");
  });
  it("should wrap methods", () => {
    expect(addon.wrappedInstance.method).toBeObject();
  });
});
