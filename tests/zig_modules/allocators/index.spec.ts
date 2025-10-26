import { describe, it, expect } from "bun:test";

import requireTestModule from "../";
const encrypt = requireTestModule("allocators");

describe("allocator", () => {
  it("should get allocator", () => {
    expect(encrypt("secret", { char: 88 })).toEqual("XXXXXX");
  });
});
