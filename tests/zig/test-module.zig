const std = @import("std");
const node_api = @import("node-api");

const TestClass = @import("TestClass.zig");
const NodeObjectTests = @import("node_values/NodeObjectTests.zig");
const WrapTarget = @import("WrapTarget.zig");
const Serialization = @import("Serialization.zig");

comptime {
    node_api.register(init);
}

fn init(node: node_api.NodeContext) !?node_api.NodeValue {
    const ptr = try std.heap.c_allocator.create(WrapTarget);
    ptr.* = .{ .foo = 123, .bar = "hopla" };

    return try node.serialize(.{
        .nodeObject = NodeObjectTests,
        .serialization = Serialization,
        .TestClass = TestClass,
        .wrappedInstance = try node.wrapInstance(WrapTarget, .{ .foo = 123, .bar = "hopla" }),
        .wrappedByConvention = ptr,
        .functions = .{
            .fnWithJsNewedNativeInstance = fnWithJsNewedNativeInstance,
            .fnWithSerializedParams = fnWithSerializedParams,
            .fnWithAllocatorParam = try node.defineFunction(fnWithAllocatorParam),
            .fnCallback = try node.defineFunction(fnCallback),
            // async must still be done explicitly
            .fnCallbackAsync = try node.defineAsyncFunction(fnCallbackAsync),
            .asyncFunction = try node.defineAsyncFunction(sleep),
        },
        .serializedValues = .{
            .arr = .{ getInt(), 12, .{ getInt(), 12 }, .{ .foo = 123 }, "bar" },
            .my_union = MyUnion{ .foo = 123 },
            .s = try node.deserialize([]u8, try node.serialize("There and Back Again.")),
            .comptime_int = try node.deserialize(i32, try node.serialize(1234)),
            .float = try node.deserialize(f32, try node.serialize(12.34)),
        },
    });
}

fn getInt() i32 {
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

fn fnWithSerializedParams(i: i32, _: bool) !f32 {
    // std.log.debug("calling zig testFuncNative2 {any} {any}", .{ i, b });

    var res: f32 = 0;
    const ii: f32 = @floatFromInt(i);
    var iii = i;
    while (iii > 0) {
        iii -= 1;
        res += ii * 1.1;
    }

    return res;
}

fn sleep(milliseconds: u32) !i32 {
    std.Thread.sleep(1000 * 1000 * milliseconds);

    return 456;
}

fn fnWithAllocatorParam(allocator: std.mem.Allocator, len: u32) ![]u8 {
    const ret = try allocator.alloc(u8, len);

    @memset(ret, @as(u8, 'A'));
    return ret;
}

fn fnWithJsNewedNativeInstance(newed_in_js: *TestClass) !*TestClass {
    newed_in_js.foo += 1;
    std.log.info("newed_in_js {any}", .{newed_in_js});
    return newed_in_js;
}

// node_api.NodeFunction(*const fn (i32) i32)

/// can be called from JS like this:
/// addon.fnCallback((value: number) => 123 + value);
fn fnCallback(arg: i32, callback: node_api.NodeFunction(fn (i32) i32)) !i32 {
    std.log.info("invoking JS callback with value 123", .{});
    // args tuple is typesafe
    const res = try callback.call(.{arg});

    std.log.info("JS callback returned: {any}", .{res});

    return res;
}

fn fnCallbackAsync(callback: node_api.NodeFunction(fn (i32) i32)) ![]const u8 {
    std.log.info("callback {any}", .{callback});

    // TODO: NodeFunction should be threadsafe (automagically)
    // args tuple is typesafe
    // const res = callback.call(.{123});

    // std.log.info("JS callback returned: {any}", .{res});

    return "ok";
}
