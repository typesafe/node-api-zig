import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("Serializer", () => {
  it("should serialize UTF8", () => {
    expect(addon.serializedValues.s).toEqual("There and Back Again.");
  });
  it("should serialize arrays", () => {
    expect(addon.serializedValues.arr).toEqual([
      -411,
      12,
      [-411, 12],
      { foo: 123 },
      "bar",
    ]);
  });
});
