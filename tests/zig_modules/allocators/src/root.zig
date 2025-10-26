const std = @import("std");
const node_api = @import("node-api");

comptime {
    node_api.@"export"(encrypt);
}

const Options = struct {
    char: u8,
};

// allocator is "injected" by convention
fn encrypt(value: []const u8, options: Options, allocator: std.mem.Allocator) ![]const u8 {
    const result = try allocator.alloc(u8, value.len);
    errdefer allocator.free(result);

    @memset(result, options.char);

    return result;
}
