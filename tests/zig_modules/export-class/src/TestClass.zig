pub fn init() @This() {
    return .{};
}

pub fn deinit(_: @This()) !void {}

pub fn method(_: @This()) ![]const u8 {
    return "method";
}

pub fn static() ![]const u8 {
    return "static";
}
