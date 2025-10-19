const std = @import("std");
const node_api = @import("node-api");

const TestClass = @import("TestClass.zig");
const Stats = @import("Stats.zig");
const WrapTarget = @import("WrapTarget.zig");
comptime {
    node_api.register(init);
}

fn init(node: node_api.NodeContext) !?node_api.NodeValue {
    // const i = getInt();
    // const ui = getUInt();
    // const b = try node.deserialize(bool, try node.serialize(true));

    // const ;

    const v = try node.serialize(.{
        .TestClass = try node.defineClass(TestClass),
        .wrappedInstance = try node.wrapInstance(WrapTarget, .{ .foo = 123, .bar = "hopla" }),
        .functions = .{
            .fnWithSerializedParams = try node.defineFunction(fnWithSerializedParams),
            .fnWithAllocatorParam = try node.defineFunction(fnWithAllocatorParam),
            .asyncFunction = try node.defineAsyncFunction(sleep),
        },
        .serializedValues = .{
            .arr = .{ getInt(), 12, .{ getInt(), 12 }, .{ .foo = 123 } },
            .my_union = MyUnion{ .foo = 123 },
            .s = try node.deserialize([]u8, try node.serialize("There and Back Again.")),
            .comptime_int = try node.deserialize(i32, try node.serialize(1234)),
            .float = try node.deserialize(f32, try node.serialize(12.34)),
        },
        // .s = s,
        // .x = x,
        // .b = b,
        // .foo = "foo",
        // .bar = "bar",
        // .int = 123,
        // .f = 12.34,
        // .i = i,
        // .ui = ui,
        // .nested = .{ .more = "foo" },
        // .callMet = try node.createFunction(),
    });

    // const v = try node.serialize(.{
    //     .fun = try node.createFunc(testFuncNative2),
    // });

    return v;
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

// fn testFunc2(node: node_api.NodeContext, args: [2]node_api.NodeValue, thiz: ?node_api.NodeValue) !?node_api.NodeValue {
//     std.log.debug("calling zig function {any}", .{node.deserialize(i32, args[0])});

//     return try node.serialize(.{ .msg = "Fucking hell!", .thiz = thiz });
// }
// fn testFunc(node: node_api.NodeContext, _: ?node_api.NodeValue) !?node_api.NodeValue {
//     std.log.info("ZIG FUNCTION testFunc", .{});
//     return try node.serialize(.{ .msg = "Fucking hell!" });
// }

fn fnWithSerializedParams(i: i32, b: bool) !i32 {
    std.log.debug("calling zig testFuncNative2 {any} {any}", .{ i, b });

    return 456;
}

fn sleep(milliseconds: u32) !i32 {
    std.Thread.sleep(1000 * 1000 * milliseconds);

    return 456;
}

fn fnWithAllocatorParam(allocator: std.mem.Allocator, len: usize) ![]u8 {
    const ret = try allocator.alloc(u8, len);

    @memset(ret, @as(u8, 'A'));
    return ret;
}
