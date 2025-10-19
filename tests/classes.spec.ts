import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("defineClass", () => {
  it("should define class as (constructor) function", () => {
    expect(addon.TestClass).toBeFunction();
  });

  // describe("static field", () => {
  //   it("should be accessible", () => {
  //     expect(addon.TestClass.instance_count).toEqual(0);
  //   });
  // });

  describe("async method", () => {
    it("should return Promise", async () => {
      const instance = new addon.TestClass(12);
      console.log(instance);
      expect(instance.methodAsync).toBeFunction();
      expect(await instance.methodAsync(123,"123")).toEqual(123);
    });
  });

  describe("static method", () => {
    it("should be callable function", () => {
      expect(addon.TestClass.static).toBeFunction();
      expect(addon.TestClass.static(123)).toEqual(246);
    });
  });
});
