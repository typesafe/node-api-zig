const std = @import("std");
const node_api = @import("node-api");

comptime {
    node_api.register(init);
}

fn init(node: node_api.NodeContext) !?node_api.NodeValue {
    std.log.info("TEST MODULE INIT (from Zig)", .{});
    // return try node.createString("hello!");
    const i = getInt();
    const ui = getUInt();
    const b = try node.deserializeValue(bool, try node.serialize(true));

    const x = try node.deserializeValue(i32, try node.serialize(1234));
    const s = try node.deserializeString(try node.serialize("string from zig to Node back to Zig"));
    const v = try node.serialize(.{
        .TestClass = try node.defineClass(TestClass),
        .wrappedInstance = try node.wrapInstance(WrapTarget, .{ .foo = 123, .bar = "hopla" }),
        .functions = .{
            .fnWithSerializedParams = try node.defineFunction(fnWithSerializedParams),
            .fnWithAllocatorParam = try node.defineFunction(fnWithAllocatorParam),
            .asyncFunction = try node.defineAsyncFunction(sleep),
        },
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
// allocated (JS `new TestClass()`) and freed/destroyed (GC finalizer) automatically
// including fields!
const TestClass = struct {
    var instance_count: usize = 0;
    const Self = @This();

    // allocator field vs allocator parameter

    foo: i32 = 123,
    // freed as part of MyModule
    // set from JS will free existing value
    // can be nested struct
    str: ?[]u8,
    // "private for JS" field
    _foo: ?[]u8 = null,

    // maps to ctor in JS (`new MyModule(123)`)
    // `ctx` is "injected" based on its type (NodeContext)
    pub fn init(ctx: node_api.NodeContext, v: i32) Self {
        std.log.debug("ctor {any} {any}", .{ ctx, v });
        instance_count += 1;
        return .{ .foo = v, .str = null };
    }

    pub fn static(s: i32) !i32 {
        return 123 + s;
    }
    // Borrow slice

    // callee allocates result/return,

    // struct creates owned memory

    /// maps to JS instance.callMe(123, "foo")
    /// ctx is injected here as well
    /// self "just works"
    /// input params and return values are serialized if they are Zig types
    /// memory allocated for s is owned,
    /// - setting it to a field will retult in free/destroy at finalize
    /// - else it needs to be freed here!
    pub fn callMe(self: Self, ctx: node_api.NodeContext, v: i32, s: []u8) !i32 {
        // self.str = s;

        std.log.debug("callMe called with arguments {any} <{any}> and '{s}'", .{ ctx, v, s });
        return v + self.foo;
    }

    pub fn methodThatOwnsParamMemory(self: Self, v: i32, s: []u8) !i32 {
        std.log.debug("callMe called with arguments <{any}> and '{s}'", .{ v, s });
        return v + self.foo;
    }

    /// NodeValues are "by ref"
    pub fn callWithParamsByRef(_: Self, _: node_api.NodeContext, v: node_api.NodeValue, s: node_api.NodeValue) !node_api.NodeValue {
        std.log.debug("callWithParamsByRef called with arguments <{any}> and '{s}'", .{ v, try s.deserializeValue([]u8) });
        return v;
    }

    /// Async method will return Promise<ReturnType>
    /// mapped to `const res = await instance.method("foo")`
    pub fn methodAsync(_: Self, _: node_api.NodeContext, v: node_api.NodeValue, s: node_api.NodeValue) !node_api.NodeValue {
        std.log.debug("in async class method {any}", .{std.Thread.getCurrentId()});
        std.log.debug("callWithParamsByRef called with arguments <{any}> and '{s}'", .{ v, try s.deserializeValue([]u8) });
        return v;
    }
};

const WrapTarget = struct {
    foo: i32,
    bar: []const u8,
    pub fn method(_: WrapTarget) !i32 {
        return 123;
    }
};
