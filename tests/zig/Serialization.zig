pub fn init() @This() {
    return @This(){};
}

// TODO: make this optional
pub fn deinit() !void {}

// TODO: do not require error union
pub fn serializeString() ![]const u8 {
    return "foo";
}

pub fn serializeI8() !i8 {
    return 8;
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

// TODO support wrapping here?
pub fn serializePointer() !*const u32 {
    return &123;
}

const Enum = enum {
    foo,
    bar,
};
