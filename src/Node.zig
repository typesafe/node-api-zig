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

    // _fields -> private fields
    // fields -> props
    // init -> ctor
    // deinit -> finalizer
    // pub fn w/ self -> method

    pub fn defineClass(self: Self, comptime T: anytype) !NodeValue {
        const info = @typeInfo(T).@"struct";

        // buffer includes len for private members, we are counting the size on-the-fly
        var prop_descriptors: [info.fields.len + info.decls.len]c.napi_property_descriptor = undefined;
        var prop_descriptors_len: usize = 0;

        inline for (info.decls) |field| {

            // // TODO
            // if (std.mem.eql(u8, field.name, "init")) {

            //     // s2e(c.napi_create_function(self.napi_env, null, 0, wrapFn(T, fun, true), null, &ctor)) catch unreachable;
            // }

            // if (std.mem.eql(u8, field.name, "deinit")) {}

            if (!std.mem.eql(u8, field.name, "init")) {
                const fun = @field(T, field.name);
                // std.log.debug("FIELD {any}", .{field.name});
                // std.log.debug("FIELD {any}", .{fun});

                // var function: c.napi_value = undefined;
                // s2e(c.napi_create_function(self.napi_env, null, 0, wrapFn(T, fun), null, &function)) catch unreachable;

                prop_descriptors[prop_descriptors_len] = c.napi_property_descriptor{
                    .utf8name = field.name,
                    .name = null,
                    .method = wrapFn(T, fun),
                    .getter = null,
                    .setter = null,
                    .value = null,
                    .attributes = c.napi_default,
                    .data = null,
                };
                prop_descriptors_len += 1;
                // const fld = @field(T, f.name);
            }
        }

        inline for (info.fields) |f| {
            std.log.debug("FIELD {any}", .{f.name});

            const fa = getFieldAccessor(T, f.name);
            const setter = getFieldSetter(T, f.name, f.type);
            prop_descriptors[prop_descriptors_len] = c.napi_property_descriptor{
                .utf8name = f.name,
                .name = null,
                .method = null,
                .getter = fa,
                .setter = setter,
                .value = null,
                .attributes = c.napi_default,
                .data = null,
            };
            prop_descriptors_len += 1;

            // .{
            //             .utf8name = "value",
            //             .name = null,
            //             .method = null,
            //             .getter = Counter.getValue,
            //             .setter = null,
            //             .value = null,
            //             .attributes = c.napi_default,
            //             .data = null,
            //         },

            //         pub fn getValue(env: c.napi_env, info: c.napi_callback_info) callconv(.C) c.napi_value {
            //     const this_val = getThis(env, info) catch return null;

            //     var raw: ?*anyopaque = null;
            //     if (c.napi_unwrap(env, this_val, &raw) != c.napi_ok or raw == null) {
            //         _ = c.napi_throw_error(env, null, "unwrap failed");
            //         return null;
            //     }
            //     const self: *Counter = @ptrCast(@alignCast(raw.?));

            //     var out: c.napi_value = null;
            //     _ = c.napi_create_double(env, @as(f64, @floatFromInt(self.value)), &out);
            //     return out;
            // }
        }

        const lifetime = getLifetimeHandler(T, @field(T, "init"), null);

        var class: c.napi_value = undefined;

        s2e(c.napi_define_class(self.napi_env, "Foo", 3, lifetime.init, null, prop_descriptors_len, &prop_descriptors, &class)) catch unreachable;

        // s2e(c.napi_create_object(self.napi_env, &class)) catch unreachable;
        // s2e(c.napi_define_properties(self.napi_env, class, prop_descriptors_len, &prop_descriptors)) catch unreachable;

        return .{ .napi_env = self.napi_env, .napi_value = class };
    }

    fn getFieldAccessor(
        comptime T: anytype,
        comptime field: []const u8,
    ) fn (env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
        return struct {
            pub fn get(env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
                const node = NodeContext{ .napi_env = env };
                var this_arg: c.napi_value = undefined;

                s2e(c.napi_get_cb_info(env, cb, null, null, &this_arg, null)) catch |err| {
                    node.handleError(err);
                    return null;
                };

                var raw: ?*anyopaque = null;
                if (c.napi_unwrap(env, this_arg, &raw) != c.napi_ok or raw == null) {
                    _ = c.napi_throw_error(env, null, "unwrap failed");
                    return null;
                }
                const self: *T = @ptrCast(@alignCast(raw.?));
                const res = @field(self, field);

                return (node.serialize(res) catch unreachable).napi_value;
            }
        }.get;
    }
    fn getFieldSetter(
        comptime T: anytype,
        comptime field: []const u8,
        comptime fieldType: type,
    ) fn (env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
        return struct {
            pub fn set(env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
                const node = NodeContext{ .napi_env = env };
                var this_arg: c.napi_value = undefined;
                var argv: [1]c.napi_value = undefined;
                var argc: usize = 1;
                s2e(c.napi_get_cb_info(env, cb, &argc, &argv, &this_arg, null)) catch |err| {
                    node.handleError(err);
                    return null;
                };

                var raw: ?*anyopaque = null;
                if (c.napi_unwrap(env, this_arg, &raw) != c.napi_ok or raw == null) {
                    _ = c.napi_throw_error(env, null, "unwrap failed");
                    return null;
                }
                const self: *T = @ptrCast(@alignCast(raw.?));
                @field(self, field) = node.deserializeValue(fieldType, NodeValue{
                    .napi_env = env,
                    .napi_value = argv[0],
                }) catch unreachable;

                return (node.getUndefined() catch unreachable).napi_value;
            }
        }.set;
    }

    fn getLifetimeHandler(comptime T: anytype, comptime init_fn: anytype, comptime _: anytype) type {
        return struct {
            pub fn init(env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
                std.log.info("init {any} {any} {any}", .{ env, cb, T });

                var new_target: c.napi_value = null;
                if (c.napi_get_new_target(env, cb, &new_target) != c.napi_ok or new_target == null) {
                    _ = c.napi_throw_error(env, null, "Constructor must be called with `new`.");
                    return null;
                }

                const params = @typeInfo(@TypeOf(init_fn)).@"fn".params;

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

                const self = std.heap.c_allocator.create(T) catch {
                    _ = c.napi_throw_error(env, null, "alloc failed");
                    return null;
                };

                self.* = @call(.auto, init_fn, fields);

                // Associate native pointer with JS object
                if (c.napi_wrap(
                    env,
                    this_arg,
                    self,
                    deinit,
                    null,
                    null,
                ) != c.napi_ok) {
                    std.heap.c_allocator.destroy(self);
                    _ = c.napi_throw_error(env, null, "napi_wrap failed");
                    return null;
                }

                return this_arg;
            }

            pub fn deinit(_: c.napi_env, data: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                std.log.info("Zig Finalizer!", .{});

                if (data) |ptr| {
                    const self: *T = @ptrCast(@alignCast(ptr));
                    std.log.info(" Finalizer data {any} {any}", .{ data, self });
                    std.heap.c_allocator.destroy(self);
                }
            }
        };
    }

    fn wrapFn(comptime T: anytype, comptime fun: anytype) fn (env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
        return opaque {
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

                // if (ctor and (params.len == 0 or params[0].type != T)) {
                //     @compileError("first argument must be self T");
                // }

                var fields: TupleTypeOf(params) = undefined;
                // std.log.info("fields: {any}", .{fields});
                if (params[0].type.? == T) {
                    var raw: ?*anyopaque = null;
                    if (c.napi_unwrap(env, this_arg, &raw) != c.napi_ok or raw == null) {
                        _ = c.napi_throw_error(env, null, "unwrap failed");
                        return null;
                    }
                    const self: *T = @ptrCast(@alignCast(raw.?));
                    fields[0] = self.*;
                }

                inline for (params[1..], 1..) |p, i| {
                    {
                        std.log.info("deserializing", .{});

                        fields[i] = node.deserializeValue(
                            p.type.?,
                            NodeValue{
                                .napi_env = node.napi_env,
                                .napi_value = args[i - 1],
                            },
                        ) catch |err| {
                            std.log.info("deserializing {any}", .{err});
                            @panic("kablammo");
                        };
                    }
                }

                const ret = @call(.auto, fun, fields);
                const res = switch (@typeInfo(@TypeOf(ret))) {
                    .error_union => ret catch |err| {
                        node.handleError(err);
                        return null;
                    },
                    else => ret,
                };

                if (@TypeOf(res) != void) {
                    return (node.serialize(res) catch |err| {
                        node.handleError(err);
                        return null;
                    }).napi_value;
                }

                return (node.getUndefined() catch {
                    @panic("kablammo");
                }).napi_value;
            }
        }.f;
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
