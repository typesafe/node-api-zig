pub fn init() @This() {
    return @This(){};
}

// TODO: make this optional
pub fn deinit() !void {}

// TODO: do not require error union
pub fn serializeString() ![]const u8 {
    return "foo";
}

pub fn serializeBool() !bool {
    return true;
}

pub fn serializeF32() !f32 {
    return 32;
}

pub fn serializeF64() !f64 {
    return 64;
}

pub fn serializeI32() !i32 {
    return 32;
}

pub fn serializeI64() !i64 {
    return 64;
}

pub fn serializeU32() !u32 {
    return 32;
}

pub fn serializeU64() !u64 {
    return 64;
}

pub fn serializeVoid() !void {
    // noop
}

pub fn serializeOptionalNull() !?u32 {
    return null;
}

pub fn serializeOptionalWithValue() !?u32 {
    return 123;
}
pub fn serializeStruct() !TestStruct {
    return .{
        .int = 123,
        .str = "first",
        .nested = .{ .int = 456, .str = "nested" },
    };
}

// TODO: do not require error union
pub fn deserializeString(val: []const u8) ![]const u8 {
    return val;
}

pub fn deserializeBool(val: bool) !bool {
    return val;
}

pub fn deserializeF32(val: f32) !f32 {
    return val;
}

pub fn deserializeF64(val: f64) !f64 {
    return val;
}

pub fn deserializeI32(val: i32) !i32 {
    return val;
}

pub fn deserializeI64(val: i64) !i64 {
    return val;
}

pub fn deserializeU32(val: u32) !u32 {
    return val;
}

pub fn deserializeU64(val: u64) !u64 {
    return val;
}

pub fn deserializeOptionalNull(val: ?u32) !?u32 {
    return val;
}

pub fn deserializeOptionalWithValue(val: ?u32) !?u32 {
    return val;
}
pub fn deserializeStruct(val: TestStruct) !TestStruct {
    return val;
}

// TODO support wrapping here?
pub fn deserializePointer(val: *const u32) !*const u32 {
    return val;
}

const Enum = enum {
    foo,
    bar,
};

const TestStruct = struct {
    int: i32,
    str: []const u8,
    nested: ?NestedTestStruct,
};

const NestedTestStruct = struct {
    int: i32,
    str: []const u8,
};
