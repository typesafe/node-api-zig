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
    pub var allocator: std.mem.Allocator = std.heap.c_allocator;

    napi_env: c.napi_env,

    pub fn init(env: c.napi_env) Self {
        return Self{ .napi_env = env };
    }

    pub fn allocateSentinel(_: Self, T: type, n: usize) !void {
        try allocator.allocSentinel(T, n, 0);
        // TODO try s2e(c.napi_adjust_external_memory(self.napi_env,n, null));
    }

    pub fn free(_: Self, memory: anytype) !void {
        try allocator.free(memory);
        // TODO try s2e(c.napi_adjust_external_memory(self.napi_env, , null));
    }

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
        const lifetime = getLifetimeHandler(T, @field(T, "init"), null);

        var class: c.napi_value = undefined;
        const props = getProps(T);
        s2e(c.napi_define_class(self.napi_env, "Foo", 3, lifetime.init, null, props.len, props.ptr, &class)) catch unreachable;

        // s2e(c.napi_create_object(self.napi_env, &class)) catch unreachable;
        // s2e(c.napi_define_properties(self.napi_env, class, prop_descriptors_len, &prop_descriptors)) catch unreachable;

        return .{ .napi_env = self.napi_env, .napi_value = class };
    }

    fn unwrapInstance(comptime T: anytype, env: c.napi_env, value: c.napi_value) !*T {
        var raw: ?*anyopaque = null;
        if (c.napi_unwrap(env, value, &raw) != c.napi_ok or raw == null) {
            return error.UnwrapFailed;
        }
        std.log.debug("unwrapped instance of {s}", .{@typeName(T)});
        return @ptrCast(@alignCast(raw.?));
    }

    fn getFieldGetter(
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
                const self = unwrapInstance(T, env, this_arg) catch {
                    _ = c.napi_throw_error(env, null, "unwrap failed");
                    return null;
                };

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

    inline fn getProps(comptime T: anytype) []c.napi_property_descriptor {
        const info = @typeInfo(T).@"struct";

        var prop_descriptors: [info.fields.len + info.decls.len]c.napi_property_descriptor = undefined;
        // `prop_descriptors` buffer includes len for private fields, init and deinit, which will be skipped,
        // so we need to track the len separately
        var prop_descriptors_len: usize = 0;

        inline for (info.decls) |decl| {
            if (!std.mem.eql(u8, decl.name, "init") and !std.mem.eql(u8, decl.name, "deinit")) {
                std.log.debug("defining method {s}.{s}", .{ @typeName(T), decl.name });

                prop_descriptors[prop_descriptors_len] = c.napi_property_descriptor{
                    .utf8name = decl.name,
                    .name = null,
                    .method = wrapFn(T, @field(T, decl.name)),
                    .getter = null,
                    .setter = null,
                    .value = null,
                    .attributes = c.napi_default,
                    .data = null,
                };
                prop_descriptors_len += 1;
            }
        }
        inline for (info.fields) |f| {
            std.log.debug("defining field {s}.{s}", .{ @typeName(T), f.name });

            prop_descriptors[prop_descriptors_len] = c.napi_property_descriptor{
                .utf8name = f.name,
                .name = null,
                .method = null,
                .getter = getFieldGetter(T, f.name),
                .setter = getFieldSetter(T, f.name, f.type),
                .value = null,
                .attributes = c.napi_default,
                .data = null,
            };
            prop_descriptors_len += 1;
        }

        return prop_descriptors[0..prop_descriptors_len];
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
                var arg: u8 = 0;
                inline for (0..params.len) |i| {
                    if (params[i].type.? == NodeContext) {
                        fields[i] = node;
                    } else {
                        fields[i] = node.deserializeValue(
                            params[i].type.?,
                            NodeValue{
                                .napi_env = node.napi_env,
                                .napi_value = args[arg],
                            },
                        ) catch |err| {
                            std.log.err("err {any}", .{err});
                            @panic("kablammo init");
                        };
                        arg += 1;
                    }
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
                    freee(T, self);
                }
            }

            /// instance is TT or *TT (due to this being called recursively)
            fn freee(comptime TT: type, instance: anytype) void {
                switch (@typeInfo(TT)) {
                    .@"struct" => |s| {
                        inline for (s.fields) |f| {
                            freee(f.type, @field(instance, f.name));
                        }
                        std.heap.c_allocator.destroy(instance);
                    },
                    // TODO more

                    .pointer => {
                        std.heap.c_allocator.destroy(instance);
                    },
                    else => {},
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

                var arg: u8 = 0;
                inline for (params[1..], 1..) |p, i| {
                    {
                        std.log.info("deserializing", .{});
                        if (params[i].type.? == NodeContext) {
                            fields[i] = node;
                        } else {
                            fields[i] = node.deserializeValue(
                                p.type.?,
                                NodeValue{
                                    .napi_env = node.napi_env,
                                    .napi_value = args[arg],
                                },
                            ) catch |err| {
                                std.log.info("deserializing {any}", .{err});
                                @panic("kablammooo");
                            };
                            arg += 1;
                        }
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

    /// Wrap a native instance in a JS object reference.
    pub fn wrapInstance(self: Self, comptime T: anytype, instance: T) !NodeValue {
        const i = try std.heap.c_allocator.create(T);
        i.* = instance;

        const props = getProps(T);

        var js_obj: c.napi_value = undefined;
        try s2e(c.napi_create_object(self.napi_env, &js_obj));
        try s2e(c.napi_define_properties(self.napi_env, js_obj, props.len, props.ptr));
        // Associate native pointer with JS object
        try s2e(c.napi_wrap(
            self.napi_env,
            js_obj,
            i,
            // TODO: associate deninit if any and free memory
            null,
            null,
            null,
        ));
        return NodeValue{ .napi_env = self.napi_env, .napi_value = js_obj };
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
                        @panic("kablammoho");
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

    pub fn deserializeString(self: Self, value: NodeValue) ![]const u8 {
        return Serializer.deserializeString(self.napi_env, value.napi_value);
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
