import { describe, it, expect } from "bun:test";

import requireTestModule from "../";
const TestClass = requireTestModule("export-class");

describe("node_api.register(type)", () => {
  it("should return class", () => {
    expect(typeof TestClass).toEqual("function");
    expect(TestClass.name).toEqual("TestClass");
    expect(TestClass.toString()).toEqual(
      "function TestClass() {\n    [native code]\n}"
    );
  });

  it("should define static memethods", () => {
    expect(typeof TestClass.static).toEqual("function");
    expect(typeof TestClass.static).toEqual("function");
    expect(TestClass.static()).toEqual("static");
  });

  it("should be constructable", () => {
    expect(new TestClass()).toEqual({});
  });

  it("should have methods", () => {
    const instance = new TestClass();
    expect(typeof instance.method).toEqual("function");
    expect(instance.method()).toEqual("method");
  });
});
