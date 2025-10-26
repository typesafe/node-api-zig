const node_api = @import("node-api");

comptime {
    node_api.@"export"(.{ .foo = "foo", .bar = 123 });
}
