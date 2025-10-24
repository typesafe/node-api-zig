import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("Convert", () => {
  describe("serialize", () => {
    it("utf8 string", () => {
      expect(addon.serialization.serializeString()).toEqual("foo");
    });
    // it("pointer", () => {
    //   expect(addon.serialization.serializePointer()).toEqual(123);
    // });
    it("bool", () => {
      expect(addon.serialization.serializeBool()).toEqual(true);
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
    it("struct", () => {
      expect(addon.serialization.serializeStruct()).toEqual({
        int: 123,
        nested: { int: 456, str: "nested" },
        str: "first",
      });
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
      expect(addon.serialization.deserializeString("foo")).toEqual("foo");
    });
    // it("pointer", () => {
    //   expect(addon.serialization.deserializePointer(123)).toEqual(123);
    // });
    it("bool", () => {
      expect(addon.serialization.deserializeBool(true)).toEqual(true);
    });

    it("i32", () => {
      expect(addon.serialization.deserializeI32(-32)).toEqual(-32);
      expect(addon.serialization.deserializeI32(32)).toEqual(32);
    });
    it("i64", () => {
      expect(addon.serialization.deserializeI64(64)).toEqual(64);
      expect(addon.serialization.deserializeI64(-64)).toEqual(-64);
    });
    it("u32", () => {
      expect(addon.serialization.deserializeU32(32)).toEqual(32);
    });
    it("u64", () => {
      expect(addon.serialization.deserializeU64(64n)).toEqual(64n);
    });
    it("f32", () => {
      expect(addon.serialization.deserializeI32(32.0)).toEqual(32);
    });
    it("f64", () => {
      expect(addon.serialization.deserializeI64(64)).toEqual(64);
    });

    it("optional null", () => {
      expect(addon.serialization.deserializeOptionalNull(null)).toBeNull();
    });
    it("optional value", () => {
      expect(addon.serialization.deserializeOptionalWithValue(123)).toEqual(
        123
      );
    });
    it("struct", () => {
      expect(
        addon.serialization.deserializeStruct({
          int: 123,
          nested: { int: 456, str: "nested" },
          str: "first",
        })
      ).toEqual({
        int: 123,
        nested: { int: 456, str: "nested" },
        str: "first",
      });
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
