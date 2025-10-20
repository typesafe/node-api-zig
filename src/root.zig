const std = @import("std");

const c = @import("c.zig").c;
const Serializer = @import("Serializer.zig");
const NodeValues = @import("node_values.zig");
/// Represents a Node VM Context.
pub const NodeContext = @import("Node.zig").NodeContext;

/// Represents a Node value.
pub const NodeValue = NodeValues.NodeValue;
pub const NodeFunction = NodeValues.NodeFunction;

/// The InitFunction to pass to the `register` method. The `ctx` parameter
/// represents the Node context. The returned value becomes the `exports` value
/// of the JS module.
pub const InitFunction = fn (ctx: NodeContext) anyerror!?NodeValue;

/// Initializes a native Node-API module. Example:
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
pub fn register(comptime init_fn: InitFunction) void {
    const module = opaque {
        pub fn napi_register_module_v1(env: c.napi_env, exp: c.napi_value) callconv(.c) c.napi_value {
            const node = NodeContext{ .napi_env = env };

            const exports = init_fn(node) catch |err| {
                node.handleError(err);
                return null;
            };

            return if (exports) |v| v.napi_value else exp;
        }
    };

    @export(&module.napi_register_module_v1, .{ .name = "napi_register_module_v1" });
}
