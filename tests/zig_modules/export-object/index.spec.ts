import { describe, it, expect } from "bun:test";

import requireTestModule from "../";
const addon = requireTestModule("export-object");

describe("node_api.register(.{})", () => {
  it("should return serialized value", () => {
    expect(addon).toEqual({ foo: "foo", bar: 123 });
  });
});
