import addon from "node-api-test-module";
import { describe, it, expect } from "bun:test";

describe("Serializer", () => {
  it("should serialize UTF8", () => {
    expect(addon.serializedValues.s).toEqual("There and Back Again.");
  });
});
