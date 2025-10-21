import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("Serializer", () => {
  describe("serialize", () => {
    it("utf8 string", () => {
      expect(addon.serialization.serializeString()).toEqual("foo");
    });
    it("pointer", () => {
      expect(addon.serialization.serializePointer()).toEqual(123);
    });
    it("bool", () => {
      expect(addon.serialization.serializeBool()).toEqual(true);
    });
    it("i8", () => {
      expect(addon.serialization.serializeI8()).toEqual(8);
    });
    it("i32", () => {
      expect(addon.serialization.serializeI32()).toEqual(32);
    });
    it("i64", () => {
      expect(addon.serialization.serializeI64()).toEqual(64);
    });
    it("u32", () => {
      expect(addon.serialization.serializeU32()).toEqual(32);
    });
    it("u64", () => {
      expect(addon.serialization.serializeU64()).toEqual(64n);
    });
    it("f32", () => {
      expect(addon.serialization.serializeI32()).toEqual(32);
    });
    it("f64", () => {
      expect(addon.serialization.serializeI64()).toEqual(64);
    });
    it("void", () => {
      expect(addon.serialization.serializeVoid()).toBeUndefined();
    });
    it("optional null", () => {
      expect(addon.serialization.serializeOptionalNull()).toBeNull();
    });
    it("optional value", () => {
      expect(addon.serialization.serializeOptionalWithValue()).toEqual(123);
    });

    it("arrays", () => {
      expect(addon.serializedValues.arr).toEqual([
        -411,
        12,
        [-411, 12],
        { foo: 123 },
        "bar",
      ]);
    });
  });
  describe("deserialize", () => {
    it("utf8 string", () => {
      expect(addon.serializedValues.s).toEqual("There and Back Again.");
    });
    it("arrays", () => {
      expect(addon.serializedValues.arr).toEqual([
        -411,
        12,
        [-411, 12],
        { foo: 123 },
        "bar",
      ]);
    });
  });
});
