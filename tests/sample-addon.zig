const std = @import("std");
const node_api = @import("node-api");

comptime {
    node_api.register(init);
}

fn init(node: node_api.Node.NodeContext) !?node_api.NodeValue {
    std.log.info("TEST MODULE INIT (from Zig)", .{});
    // return try node.createString("hello!");
    const i = getInt();
    const ui = getUInt();
    return try node.serialize(.{
        .foo = "foo",
        .bar = "bar",
        .int = 123,
        .f = 12.34,
        .i = i,
        .ui = ui,
        .nested = .{ .more = "foo" },
        .arr = .{ getInt(), 12, .{ getInt(), 12 }, .{ .foo = 123 } },
        .my_union = MyUnion{ .foo = 123 },
        // .callMet = try node.createFunction(),
    });
}

fn getInt() i16 {
    return -456 + 45;
}
fn getUInt() u16 {
    return 456 + 45;
}

const MyUnionTag = enum {
    foo,
    bar,
};
const MyUnion = union(MyUnionTag) { foo: u32, bar: []const u8 };
