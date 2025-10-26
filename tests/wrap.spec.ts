import { describe, it, expect } from "bun:test";

import requireTestModule from "./zig_modules";
const addon = requireTestModule("test-module");

describe("wrapInstance", () => {
  it("should wrap instance", () => {
    expect(addon.wrappedInstance).toBeObject();
  });
  it("should wrap by convention", () => {
    expect(addon.wrappedByConvention).toBeObject();
    addon.wrappedByConvention.foo = 456;
    expect(addon.wrappedByConvention.foo).toEqual(456);
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
