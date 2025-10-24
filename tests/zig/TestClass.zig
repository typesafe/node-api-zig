const std = @import("std");
const node_api = @import("node-api");

const WrapTarget = @import("WrapTarget.zig");

// allocated (JS `new TestClass()`) and freed/destroyed (GC finalizer) automatically
// including fields!

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

pub fn deinit(_: Self) !void {
    std.log.debug("in deinit", .{});
    instance_count -= 1;
}

pub fn getInstanceCount() !usize {
    return instance_count;
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

pub fn handleWrappedValue(_: Self, wrapped: *WrapTarget) !void {
    // self.str = s;

    std.log.debug("callMe called with wrapped value {*} {any}", .{ wrapped, wrapped });
}

pub fn methodThatOwnsParamMemory(self: Self, v: i32, s: []u8) !i32 {
    std.log.debug("callMe called with arguments <{any}> and '{s}'", .{ v, s });
    return v + self.foo;
}

/// NodeValues are "by ref"
pub fn callWithParamsByRef(_: Self, node: node_api.NodeContext, v: node_api.NodeValue, s: node_api.NodeValue) !node_api.NodeValue {
    std.log.debug("callWithParamsByRef called with arguments <{any}> and '{s}'", .{ v, try node.deserialize([]u8, s) });
    return v;
}

/// Async method will return Promise<ReturnType>
/// mapped to `const res = await instance.method("foo")`
pub fn methodAsync(_: Self, node: node_api.NodeContext, v: node_api.NodeValue, s: node_api.NodeValue) !node_api.NodeValue {
    std.log.debug("in async class method {any}", .{std.Thread.getCurrentId()});
    std.log.debug("callWithParamsByRef called with arguments <{any}> and '{s}'", .{ v, try node.deserialize([]u8, s) });
    return v;
}
