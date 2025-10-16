const std = @import("std");
const node_api = @import("node-api");

comptime {
    node_api.register(init);
}

const allocator = std.heap.page_allocator;

fn init(node: node_api.NodeContext) !?node_api.NodeValue {
    std.log.info("TEST MODULE INIT (from Zig)", .{});
    // return try node.createString("hello!");
    const i = getInt();
    const ui = getUInt();
    const b = try node.deserializeValue(bool, try node.serialize(true));

    const x = try node.deserializeValue(i32, try node.serialize(1234));
    const s = try node.deserializeString(try node.serialize("string from zig to Node back to Zig"));
    const v = try node.serialize(.{
        .C = try node.defineClass(MyModule),
        .fun2 = try node.createFunction(2, testFunc2),
        .fun = try node.createFunction(0, testFunc),
        // .afun = try node.createAsyncFunction(0, testFunc),
        .nfun = try node.createFunc(testFuncNative2),
        .s = s,
        .x = x,
        .b = b,
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

fn testFunc2(node: node_api.NodeContext, args: [2]node_api.NodeValue, thiz: ?node_api.NodeValue) !?node_api.NodeValue {
    std.log.debug("calling zig function {any}", .{node.deserializeValue(i32, args[0])});

    return try node.serialize(.{ .msg = "Fucking hell!", .thiz = thiz });
}
fn testFunc(node: node_api.NodeContext, _: ?node_api.NodeValue) !?node_api.NodeValue {
    std.log.info("ZIG FUNCTION testFunc", .{});
    return try node.serialize(.{ .msg = "Fucking hell!" });
}

fn testFuncNative2(i: i32, b: bool) !i32 {
    std.log.debug("calling zig testFuncNative2 {any} {any}", .{ i, b });

    return 456;
}

const MyModule = struct {
    // allocator that will be used to allocate memory of arguments, node.allocator will be used as default
    // allocator

    foo: i32 = 123,
    str: ?[]u8,

    pub fn init(ctx: node_api.NodeContext, v: i32) MyModule {
        std.log.debug("ctor {any} {any}", .{ ctx, v });
        return .{ .foo = v, .str = null };
    }

    // ctx is injected automatically
    pub fn callMe(self: @This(), ctx: node_api.NodeContext, v: i32, s: []u8) !i32 {
        std.log.debug("callMe called with arguments {any} <{any}> and '{s}'", .{ ctx, v, s });
        return v + self.foo;
    }

    // s is owned!
    pub fn methodThatOwnsParamMemory(self: @This(), v: i32, s: []u8) !i32 {
        std.log.debug("callMe called with arguments <{any}> and '{s}'", .{ v, s });
        return v + self.foo;
    }

    pub fn callWithParamsByRef(_: @This(), _: node_api.NodeContext, v: node_api.NodeValue, s: node_api.NodeValue) !node_api.NodeValue {
        std.log.debug("callWithParamsByRef called with arguments <{any}> and '{s}'", .{ v, try s.deserializeValue([]u8) });
        return v;
    }
};
