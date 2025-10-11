const std = @import("std");
const lib = @import("c.zig");
const Serializer = @import("Serializer.zig");

const c = lib.c;
const NodeApiError = lib.NodeApiError;
const s2e = lib.statusToError;

/// Defines a NodeFunction with the specified nuymber of arguments.
pub fn NodeFunction(comptime arg_count: usize) type {
    if (arg_count > 0) {
        return fn (ctx: NodeContext, args: [arg_count]Serializer.NodeValue, thiz: ?Serializer.NodeValue) anyerror!?Serializer.NodeValue;
    }

    return fn (ctx: NodeContext, thiz: ?Serializer.NodeValue) anyerror!?Serializer.NodeValue;
}

/// Represents a context that the underlying Node-API implementation can use to persist VM-specific state.
pub const NodeContext = struct {
    const Self = @This();

    napi_env: c.napi_env,

    /// Creates a JS-accessible function.
    pub fn createFunction(self: Self, comptime arg_count: usize, fun: NodeFunction(arg_count)) !Serializer.NodeValue {
        const f = opaque {
            pub fn f(env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
                const node = NodeContext{ .napi_env = env };

                var this_arg: c.napi_value = undefined;
                var args: [arg_count]c.napi_value = undefined;
                var argc = arg_count;

                s2e(c.napi_get_cb_info(env, cb, &argc, &args, &this_arg, null)) catch |err| {
                    node.handleError(err);
                    return null;
                };

                const this = if (this_arg == null) null else Serializer.NodeValue{ .napi_env = env, .napi_value = this_arg };

                if (argc < arg_count) {
                    std.log.warn("arg count {any} < {any}", .{ argc, arg_count });
                } else if (argc > arg_count) {
                    std.log.warn("arg count {any} > {any}", .{ argc, arg_count });
                }

                const ret = if (arg_count == 0)
                    fun(node, this)
                else
                    fun(node, wrapNapiValues(env, arg_count, args), this);

                const res = ret catch |err| {
                    node.handleError(err);
                    return null;
                };

                return if (res) |v| v.napi_value else null;
            }
        }.f;

        var function: c.napi_value = undefined;
        try s2e(c.napi_create_function(self.napi_env, null, 4, f, null, &function));
        return Serializer.NodeValue{ .napi_env = self.napi_env, .napi_value = function };
    }

    pub fn serialize(self: Self, value: anytype) !Serializer.NodeValue {
        return .{
            .napi_env = self.napi_env,
            .napi_value = try (Serializer{ .napi_env = self.napi_env }).serialize(value),
        };
    }

    pub fn deserializeValue(self: Self, comptime T: type, value: Serializer.NodeValue) !T {
        return (Serializer{ .napi_env = self.napi_env }).deserializeValue(T, value.napi_value);
    }

    pub fn deserializeString(self: Self, value: Serializer.NodeValue, allocator: std.mem.Allocator) ![]const u8 {
        return (Serializer{ .napi_env = self.napi_env }).deserializeString(value.napi_value, allocator);
    }

    pub fn handleError(self: Self, err: anyerror) void {
        lib.handleError(self.napi_env, err);
    }
};

fn wrapNapiValues(env: c.napi_env, comptime count: usize, args: [count]c.napi_value) [count]Serializer.NodeValue {
    var result: [count]Serializer.NodeValue = undefined;
    for (args, 0..) |arg, i| {
        result[i] = Serializer.NodeValue{ .napi_env = env, .napi_value = arg };
    }
    return result;
}
