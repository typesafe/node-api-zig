import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("NodeObject", () => {
  describe("has", () => {
    it("should return true for existing ", () => {
      expect(addon.nodeObject.has({ prop: "bar" })).toEqual(true);
    });
    it("should return false for non-existing ", () => {
      expect(addon.nodeObject.has({ foo: "bar" })).toEqual(false);
    });
  });

  describe("hasOwn", () => {
    it("should return true for existing ", () => {
      expect(addon.nodeObject.hasOwn({ prop: "bar" })).toEqual(true);
    });
    it("should return false for non-existing ", () => {
      expect(addon.nodeObject.hasOwn({ foo: "bar" })).toEqual(false);
    });
  });

  describe("getPropertyNames", () => {
    it("should return array of properties ", () => {
      const obj = { foo: "foo", bar: 123 };

      expect(addon.nodeObject.getPropertyNames(obj)).toEqual(["foo", "bar"]);
    });
  });

  describe("get", () => {
    it("should return value of existing prop ", () => {
      expect(addon.nodeObject.get({ prop: "bar" })).toEqual("bar");
    });
    it("should return undefined for non-existing ", () => {
      expect(addon.nodeObject.get({ foo: "bar" })).toEqual(undefined);
    });
  });

  describe("get", () => {
    it("should return value of existing prop ", () => {
      expect(addon.nodeObject.get({ prop: "bar" })).toEqual("bar");
    });
    it("should return undefined for non-existing ", () => {
      expect(addon.nodeObject.get({ foo: "bar" })).toEqual(undefined);
    });
  });

  describe("set", () => {
    it("should set value of existing prop ", () => {
      const obj = { prop: "bar" };
      expect(addon.nodeObject.set(obj, "foo")).toEqual("foo");
      expect(obj.prop).toEqual("foo");
    });
    it("should add prop if non-existing ", () => {
      const obj = { other: "bar" } as any;
      expect(addon.nodeObject.set(obj, "foo")).toEqual("foo");
      expect(obj.prop).toEqual("foo");
    });
  });

  describe("delete", () => {
    it("should remove key for existing prop ", () => {
      const obj = { prop: "bar" } as any;
      expect(addon.nodeObject.delete(obj)).toEqual(true);
      expect(obj).toEqual({});
    });
    it("should return undefined for non-existing ", () => {
      const obj = { foo: "bar" } as any;
      expect(addon.nodeObject.delete(obj)).toEqual(true);
      expect(obj).toEqual({ foo: "bar" });
    });
  });
});
