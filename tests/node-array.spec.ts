import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("NodeArray", () => {
  describe("len", () => {
    it("should return zero for empty array ", () => {
      expect(addon.nodeArray.len([])).toEqual(0);
    });
    it("should return length of non-emtpy array ", () => {
      expect(addon.nodeArray.len([123, 123, 123])).toEqual(3);
    });
  });

  describe("get", () => {
    it("should get value of index", () => {
      expect(addon.nodeArray.get([123, 456], 1)).toEqual(456);
    });
    it("should get undefined for invalid index ", () => {
      expect(addon.nodeArray.get([], 1)).toEqual(undefined);
    });
  });

  describe("set", () => {
    it("should set value at index", () => {
      const arr = [1, 2, 3] as any[];
      expect(addon.nodeArray.set(arr, 1, "foo")).toEqual("foo");
      expect(arr).toEqual([1, "foo", 3]);
    });
    it("should set value at index past len", () => {
      const arr = [1, 2, 3] as any[];
      expect(addon.nodeArray.set(arr, 5, "foo")).toEqual("foo");
      expect(arr).toEqual([1, 2, 3, undefined, undefined, "foo"]);
    });
  });
});
