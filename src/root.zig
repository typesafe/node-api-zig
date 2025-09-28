const std = @import("std");

const c = @import("c.zig").c;
pub const Node = @import("Node.zig");

pub const InitFunction = fn (ctx: Node.NodeContext) anyerror!Node.NodeValue;

pub fn register(comptime init: InitFunction) void {
    const module = opaque {
        pub fn napi_register_module_v1(env: c.napi_env, _: c.napi_value) callconv(.c) c.napi_value {
            const node = Node.NodeContext{ .napi_env = env };
            const exp = init(node) catch {
                // node.throwError("failed to initialize native Zig module") catch {
                @panic("failed to throw error after failed module init");
                // };
            };

            return exp.napi_value;
        }
    };

    @export(&module.napi_register_module_v1, .{ .name = "napi_register_module_v1" });
}
