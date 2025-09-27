const std = @import("std");
const node_api = @import("node-api");

comptime {
    node_api.register(init);
}

fn init() void {
    std.log.info("TEST MODULE INIT (from Zig)", .{});
}
