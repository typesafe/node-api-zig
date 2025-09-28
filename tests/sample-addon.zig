const std = @import("std");
const node_api = @import("node-api");

comptime {
    node_api.register(init);
}

fn init(node: node_api.Node.NodeContext) !node_api.Node.NodeValue {
    std.log.info("TEST MODULE INIT (from Zig)", .{});
    return try node.createString("hello!");
}
