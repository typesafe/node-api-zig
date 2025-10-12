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

// /// Defines a NodeFunction with the specified nuymber of arguments.
// pub fn NodeFunction(comptime arg_count: usize) type {
//     if (arg_count > 0) {
//         return fn (ctx: NodeContext, args: [arg_count]Serializer.NodeValue, thiz: ?Serializer.NodeValue) anyerror!?Serializer.NodeValue;
//     }

//     return fn (ctx: NodeContext, thiz: ?Serializer.NodeValue) anyerror!?Serializer.NodeValue;
// }

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

    /// Creates a JS-accessible function.
    pub fn createFunc(self: Self, comptime fun: anytype) !Serializer.NodeValue {
        const f = opaque {
            pub fn f(env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
                const node = NodeContext{ .napi_env = env };
                const params = @typeInfo(@TypeOf(fun)).@"fn".params;
                var this_arg: c.napi_value = undefined;
                var args: [params.len]c.napi_value = undefined;
                var argc = params.len;

                s2e(c.napi_get_cb_info(env, cb, &argc, &args, &this_arg, null)) catch |err| {
                    node.handleError(err);
                    return null;
                };

                // const this = if (this_arg == null) null else Serializer.NodeValue{ .napi_env = env, .napi_value = this_arg };

                comptime var argTypes: [params.len]type = undefined;
                inline for (0..params.len) |i| {
                    argTypes[i] = params[i].type.?;
                }

                const t = std.meta.Tuple(&argTypes);
                var fields: t = undefined;
                inline for (0..params.len) |i| {
                    fields[i] = node.deserializeValue(
                        params[i].type.?,
                        Serializer.NodeValue{
                            .napi_env = env,
                            .napi_value = args[i],
                        },
                    ) catch {
                        @panic("kablammo");
                    };
                }
                const ret = @call(.auto, fun, fields);

                const res = ret catch |err| {
                    node.handleError(err);
                    return null;
                };

                return (node.serialize(res) catch |err| {
                    node.handleError(err);
                    return null;
                }).napi_value;
            }
        }.f;

        var function: c.napi_value = undefined;
        try s2e(c.napi_create_function(self.napi_env, null, 0, f, null, &function));
        return Serializer.NodeValue{ .napi_env = self.napi_env, .napi_value = function };
    }

    /// Creates a JS-accessible function.
    pub fn createAsyncFunction(self: Self, comptime arg_count: usize, fun: NodeFunction(arg_count)) !Serializer.NodeValue {
        const f = opaque {
            pub fn f(env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
                const n = NodeContext{ .napi_env = env };

                var this_arg: c.napi_value = undefined;
                var args: [arg_count]c.napi_value = undefined;
                var argc = arg_count;

                s2e(c.napi_get_cb_info(env, cb, &argc, &args, &this_arg, null)) catch |err| {
                    n.handleError(err);
                    return null;
                };
                const this = if (this_arg == null) null else Serializer.NodeValue{ .napi_env = env, .napi_value = this_arg };

                const handler = opaque {
                    pub fn work(e: c.napi_env, data: ?*anyopaque) callconv(.c) void {
                        std.log.info("worker thread {any}", .{std.Thread.getCurrentId()});
                        const node = NodeContext{ .napi_env = e };
                        var state: *AsyncState = @ptrCast(@alignCast(data));

                        // std.log.info("state {any}", .{state});
                        // std.log.info("state {any}", .{state});
                        const ret = if (arg_count == 0)
                            fun(node, state.this)
                        else
                            fun(node, wrapNapiValues(e, arg_count, state.args), this);

                        std.log.info("ret {any}", .{ret});
                        const res = ret catch |err| {
                            std.log.info("ERROR {any}", .{err});
                            node.handleError(err);
                            state.err = err;
                            return;
                        };

                        std.log.info("RETURN {any}", .{res});
                        if (res) |v| {
                            state.return_value = v.napi_value;
                        }
                    }

                    pub fn resolve(c_env: c.napi_env, _: c_uint, data: ?*anyopaque) callconv(.c) void {
                        var state: *AsyncState = @ptrCast(@alignCast(data));

                        std.log.info("DATA {any}", .{data.?});
                        std.log.info("completion thread {any}", .{std.Thread.getCurrentId()});

                        std.Thread.sleep(1000 * 1000 * 1000 * 5);
                        var dbl: c.napi_value = undefined;
                        _ = c.napi_create_double(c_env, 12.23, &dbl);
                        const res = s2e(c.napi_resolve_deferred(c_env, state.deferred, dbl)) catch |err| {
                            state.err = err;
                            return;
                        };
                        std.log.info("res {any}", .{res});
                    }
                };

                var deferred: c.napi_deferred = undefined;
                var promise: c.napi_value = undefined;
                s2e(c.napi_create_promise(env, &deferred, &promise)) catch |err| {
                    n.handleError(err);
                    return null;
                };

                const s = std.heap.page_allocator.create(AsyncState) catch {
                    @panic("bam");
                };
                s.*.deferred = deferred;
                s.*.this = this;
                s.*.args = &args;
                s.*.return_value = null;

                var task: c.napi_async_work = undefined;
                s2e(c.napi_create_async_work(
                    env,
                    null,
                    null,
                    handler.work,
                    handler.resolve,
                    s,
                    &task,
                )) catch |err| {
                    n.handleError(err);
                    return null;
                };
                s2e(c.napi_queue_async_work(env, task)) catch |err| {
                    n.handleError(err);
                    return null;
                };

                return promise;
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

const AsyncState = struct {
    deferred: c.napi_deferred,
    this: ?Serializer.NodeValue,
    args: []c.napi_value,
    return_value: c.napi_value = null,
    err: ?anyerror = null,
};
