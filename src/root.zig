const std = @import("std");

const c = @import("c.zig").c;
const Convert = @import("Convert.zig");
const NodeValues = @import("node_values.zig");

pub const NodeContext = @import("Node.zig").NodeContext;
pub const NodeValue = NodeValues.NodeValue;
pub const NodeObject = NodeValues.NodeObject;
pub const NodeArray = NodeValues.NodeArray;
pub const NodeFunction = NodeValues.NodeFunction;

/// Exports the specified comptime value as a native Node-API module.
///
/// Example:
///
/// ```
/// const std = @import("std");
/// const node_api = @import("node-api");
///
/// comptime {
///     node_api.@"export"(.{
///         .fn = function,
///         .Class = Class,
///     });
/// }
/// ```
pub fn @"export"(comptime value: anytype) void {
    const module = opaque {
        pub fn napi_register_module_v1(env: c.napi_env, _: c.napi_value) callconv(.c) c.napi_value {
            const node = NodeContext.init(env);

            const exports = node.serialize(value) catch |err| {
                node.handleError(err);
                return null;
            };

            return exports.napi_value;
        }
    };

    registerModule(&module.napi_register_module_v1);
}

/// Initializes a native Node-API module by returning a runtime-known value.
///
/// Example:
///
/// ```
/// const std = @import("std");
/// const node_api = @import("node-api");
///
/// comptime {
///     node_api.register(init);
/// }
///
/// fn init(node: node_api.Node.NodeContext) !node_api.Node.NodeValue {
///     std.log.info("TEST MODULE INIT (from Zig)", .{});
///     return try node.createString("hello!");
/// }
/// ```
pub fn init(comptime f: InitFunction) void {
    const module = opaque {
        pub fn napi_register_module_v1(env: c.napi_env, exp: c.napi_value) callconv(.c) c.napi_value {
            const node = NodeContext.init(env);

            const exports = f(node) catch |err| {
                node.handleError(err);
                return null;
            };

            return if (exports) |v| v.napi_value else exp;
        }
    };

    registerModule(&module.napi_register_module_v1);
}

/// The InitFunction to pass to the `register` method. The `ctx` parameter
/// represents the Node context. The returned value becomes the `exports` value
/// of the JS module.
pub const InitFunction = fn (ctx: NodeContext) anyerror!?NodeValue;

inline fn registerModule(comptime ptr: *const anyopaque) void {
    @export(ptr, .{ .name = "napi_register_module_v1" });
}
