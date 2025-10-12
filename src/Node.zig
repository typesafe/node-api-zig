const std = @import("std");
const lib = @import("c.zig");

const NodeValues = @import("node_values.zig");
const NodeValue = NodeValues.NodeValue;

const Serializer = @import("Serializer.zig");

const c = lib.c;
const NodeApiError = lib.NodeApiError;
const s2e = lib.statusToError;

/// Defines a NodeFunction with the specified nuymber of arguments.
pub fn NodeFunction(comptime arg_count: usize) type {
    if (arg_count > 0) {
        return fn (ctx: NodeContext, args: [arg_count]NodeValue, thiz: ?NodeValue) anyerror!?NodeValue;
    }

    return fn (ctx: NodeContext, thiz: ?NodeValue) anyerror!?NodeValue;
}

/// Represents a context that the underlying Node-API implementation can use to persist VM-specific state.
pub const NodeContext = struct {
    const Self = @This();

    napi_env: c.napi_env,

    pub fn getNull(self: Self) !NodeValue {
        return self.get(c.napi_get_null);
    }

    pub fn getUndefined(self: Self) !NodeValue {
        return self.get(c.napi_get_undefined);
    }

    /// Creates a JS-accessible function.
    pub fn createFunction(self: Self, comptime arg_count: usize, fun: NodeFunction(arg_count)) !NodeValue {
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

                const this = if (this_arg == null) null else NodeValue{ .napi_env = env, .napi_value = this_arg };

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
        return NodeValue{ .napi_env = self.napi_env, .napi_value = function };
    }

    /// Creates a JS-accessible function.
    ///
    /// TODO: `this` support?
    ///
    /// `fun` must be a function with zero or more parameters. Parameters can be of type
    /// - `NodeValue`: this is usefule to access JS objects by reference.
    /// - a supported Zig type: The JS function arguments will be deserialized.
    ///
    pub fn createFunc(self: Self, comptime fun: anytype) !NodeValue {
        const f = opaque {
            pub fn f(env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
                const params = switch (@typeInfo(@TypeOf(fun))) {
                    .@"fn" => |t| t.params,
                    else => @compileError("fun must be a function"),
                };

                const node = NodeContext{ .napi_env = env };
                var this_arg: c.napi_value = undefined;
                var args: [params.len]c.napi_value = undefined;
                var argc = params.len;

                s2e(c.napi_get_cb_info(env, cb, &argc, &args, &this_arg, null)) catch |err| {
                    node.handleError(err);
                    return null;
                };

                // const this = if (this_arg == null) null else NodeValue{ .napi_env = env, .napi_value = this_arg };
                var fields: TupleTypeOf(params) = undefined;
                inline for (0..params.len) |i| {
                    fields[i] = node.deserializeValue(
                        params[i].type.?,
                        NodeValue{
                            .napi_env = node.napi_env,
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
        return NodeValue{ .napi_env = self.napi_env, .napi_value = function };
    }

    /// Creates a JS-accessible function.
    pub fn createAsyncFunction(self: Self, comptime arg_count: usize, fun: NodeFunction(arg_count)) !NodeValue {
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
                const this = if (this_arg == null) null else NodeValue{ .napi_env = env, .napi_value = this_arg };

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
        return NodeValue{ .napi_env = self.napi_env, .napi_value = function };
    }

    pub fn serialize(self: Self, value: anytype) !NodeValue {
        return .{
            .napi_env = self.napi_env,
            .napi_value = try Serializer.serialize(self.napi_env, value),
        };
    }

    pub fn deserializeValue(self: Self, comptime T: type, value: NodeValue) !T {
        return Serializer.deserializeValue(self.napi_env, T, value.napi_value);
    }

    pub fn deserializeString(self: Self, value: NodeValue, allocator: std.mem.Allocator) ![]const u8 {
        return Serializer.deserializeString(self.napi_env, value.napi_value, allocator);
    }

    pub fn handleError(self: Self, err: anyerror) void {
        lib.handleError(self.napi_env, err);
    }

    fn get(self: Self, f: anytype) !NodeValue {
        var res: c.napi_value = undefined;
        try s2e(f(self.napi_env, &res));
        return NodeValue{ .napi_env = self.napi_env, .napi_value = res };
    }
};

fn wrapNapiValues(env: c.napi_env, comptime count: usize, args: [count]c.napi_value) [count]NodeValue {
    var result: [count]NodeValue = undefined;
    for (args, 0..) |arg, i| {
        result[i] = NodeValue{ .napi_env = env, .napi_value = arg };
    }
    return result;
}

const AsyncState = struct {
    deferred: c.napi_deferred,
    this: ?NodeValue,
    args: []c.napi_value,
    return_value: c.napi_value = null,
    err: ?anyerror = null,
};

fn TupleTypeOf(comptime params: []const std.builtin.Type.Fn.Param) type {
    comptime var argTypes: [params.len]type = undefined;
    inline for (0..params.len) |i| {
        argTypes[i] = params[i].type.?;
    }

    return std.meta.Tuple(&argTypes);
}
