foo: i32,
bar: []const u8,
pub fn method(_: @This()) !i32 {
    return 123;
}
