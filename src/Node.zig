const std = @import("std");

const lib = @import("c.zig");
const c = lib.c;
const NodeApiError = lib.NodeApiError;
const s2e = lib.statusToError;

const Convert = @import("Convert.zig");

const NodeValues = @import("node_values.zig");
const NodeValue = NodeValues.NodeValue;

const registry = @import("references.zig").Registry;

/// Represents a context that the underlying Node-API implementation can use to persist VM-specific state.
pub const NodeContext = struct {
    const Self = @This();

    napi_env: c.napi_env,

    pub fn init(env: c.napi_env) Self {
        return Self{ .napi_env = env };
    }

    pub fn getNull(self: Self) !NodeValue {
        return self.get(c.napi_get_null);
    }

    pub fn getUndefined(self: Self) !NodeValue {
        return self.get(c.napi_get_undefined);
    }

    pub fn defineClass(self: Self, comptime T: anytype) !NodeValue {
        // @typeInfo(T).@"struct".decls
        // if (!@hasDecl(T, "init")) {
        //     @compileError("Class definitions must have init method to serve as JS constructor.");
        // }

        const lifetime = getLifetimeHandler(T);
        const props = getProps(T);
        var class: c.napi_value = undefined;
        s2e(c.napi_define_class(self.napi_env, @typeName(T), @typeName(T).len, lifetime.init, null, props.len, props.ptr, &class)) catch unreachable;

        return NodeValue.init(self.napi_env, class);
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

                // TODO: use self.allocator if any
                //@hasField(T, "allocator");

                @field(self, field) = node.deserialize(fieldType, NodeValue{
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

        if (@hasDecl(T, "instance_count")) {
            std.log.debug("`instance_count` exists, type = {s}\n", .{@typeName(@TypeOf(T.instance_count))});
        } else {
            std.log.debug("instance_count does not exist", .{});
        }

        inline for (info.decls) |decl| {
            if (!std.mem.eql(u8, decl.name, "init") and !std.mem.eql(u8, decl.name, "deinit")) {
                std.log.debug("defining method {s}.{s} {any}", .{ @typeName(T), decl.name, decl.name.len });
                const fun = @field(T, decl.name);

                prop_descriptors[prop_descriptors_len] = c.napi_property_descriptor{
                    .utf8name = decl.name,
                    .name = null,
                    .method = if (endsWith(decl.name, "Async")) wrapAsyncFunction(T, fun) else wrapFn(T, fun),
                    .getter = null,
                    .setter = null,
                    .value = null,
                    .attributes = if (isStatic(T, fun)) c.napi_static else c.napi_default,
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

    fn getLifetimeHandler(comptime T: anytype) type {
        return struct {
            pub fn init(env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
                std.log.info("init {any} {any} {any}", .{ env, cb, T });

                var new_target: c.napi_value = null;
                if (c.napi_get_new_target(env, cb, &new_target) != c.napi_ok or new_target == null) {
                    _ = c.napi_throw_error(env, null, "Constructor must be called with `new`.");
                    return null;
                }

                // TODO: if no init, use args object to set fields
                // TODO: if no fields -> treat as namespace
                // if (@hasField(T, "init")) {}

                const init_fn = @field(T, "init");

                const params = @typeInfo(@TypeOf(init_fn)).@"fn".params;

                const node = NodeContext{ .napi_env = env };
                var this_arg: c.napi_value = undefined;
                var args: [params.len]c.napi_value = undefined;
                var argc = params.len;

                s2e(c.napi_get_cb_info(env, cb, &argc, &args, &this_arg, null)) catch |err| {
                    node.handleError(err);
                    return null;
                };

                // TODO:
                var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
                defer arena.deinit();

                // const this = if (this_arg == null) null else NodeValue{ .napi_env = env, .napi_value = this_arg };
                var fields: TupleTypeOf(params) = undefined;
                var arg: u8 = 0;
                inline for (0..params.len) |i| {
                    if (params[i].type.? == NodeContext) {
                        fields[i] = node;
                    } else {
                        fields[i] = node.deserialize(
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
                    finalize,
                    null,
                    null,
                ) != c.napi_ok) {
                    std.heap.c_allocator.destroy(self);
                    _ = c.napi_throw_error(env, null, "napi_wrap failed");
                    return null;
                }

                registry.track(self, this_arg) catch unreachable;

                return this_arg;
            }

            pub fn finalize(e: c.napi_env, data: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                std.log.info("Zig Finalizer!", .{});

                // TODO: if deinit -> struct is responinsible for free?
                if (@hasDecl(T, "deinit")) {
                    const deinit_fn = @field(T, "deinit");
                    _ = callFunction(T, deinit_fn, NodeContext.init(e), .{ .zig = data }, &.{}) catch |err| {
                        _ = err;
                        // TODO How do we deal with this? Finalizers are invoked in the background.
                        unreachable;
                    };
                } else {
                    const self: *T = @ptrCast(@alignCast(data.?));
                    std.log.info(" Finalizer data {any} {any}", .{ data, self });
                    freee(T, self);
                    registry.untrack(self);
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

    fn isStatic(comptime T: anytype, comptime fun: anytype) bool {
        const params = switch (@typeInfo(@TypeOf(fun))) {
            .@"fn" => |t| t.params,
            else => @compileError("fun must be a function"),
        };

        return params.len == 0 or params[0].type != T;
    }

    fn wrapFn(comptime T: anytype, comptime fun: anytype) fn (env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
        const params = switch (@typeInfo(@TypeOf(fun))) {
            .@"fn" => |t| t.params,
            else => @compileError("`fun` must be a function."),
        };

        return opaque {
            pub fn f(env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
                const node = NodeContext{ .napi_env = env };
                var this_arg: c.napi_value = undefined;
                var args: [params.len]c.napi_value = undefined;
                var argc: usize = params.len;

                s2e(c.napi_get_cb_info(env, cb, &argc, &args, &this_arg, null)) catch |err| {
                    node.handleError(err);
                    return null;
                };

                return callFunction(
                    T,
                    fun,
                    node,
                    .{ .js = this_arg },
                    args[0..argc],
                ) catch |err| {
                    node.handleError(err);
                    return null;
                };
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
        try registry.track(i, js_obj);
        return NodeValue{ .napi_env = self.napi_env, .napi_value = js_obj };
    }

    /// Defines a JS-accessible function.
    ///
    ///
    /// `fun` must be a function with zero or more parameters. Parameters and return type can be of type
    /// - `NodeValue`: this is useful to access JS objects by reference.
    /// - a supported Zig type: The JS function arguments will be deserialized.
    ///
    pub fn defineFunction(self: Self, comptime fun: anytype) !NodeValue {
        var function: c.napi_value = undefined;
        try s2e(c.napi_create_function(self.napi_env, null, 0, wrapFn(struct {}, fun), null, &function));
        return NodeValue{ .napi_env = self.napi_env, .napi_value = function };
    }

    pub fn defineAsyncFunction(self: Self, fun: anytype) !NodeValue {
        var function: c.napi_value = undefined;
        try s2e(c.napi_create_function(self.napi_env, null, 4, wrapAsyncFunction(null, fun), null, &function));
        return NodeValue{ .napi_env = self.napi_env, .napi_value = function };
    }

    /// Creates a JS-accessible Async function.
    fn wrapAsyncFunction(comptime T: anytype, fun: anytype) fn (env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
        const params = switch (@typeInfo(@TypeOf(fun))) {
            .@"fn" => |t| t.params,
            else => @compileError("`fun` must be a function."),
        };
        const return_type = switch (@typeInfo(@TypeOf(fun))) {
            .@"fn" => |t| t.return_type,
            else => @compileError("`fun` must be a function."),
        };

        return opaque {
            pub fn f(env: c.napi_env, cb: c.napi_callback_info) callconv(.c) c.napi_value {
                const node = NodeContext{ .napi_env = env };
                var this_arg: c.napi_value = undefined;
                var args: [params.len]c.napi_value = undefined;
                var argc: usize = params.len;

                s2e(c.napi_get_cb_info(env, cb, &argc, &args, &this_arg, null)) catch |err| {
                    node.handleError(err);
                    return null;
                };

                const ThisAsyncState = AsyncState(params, return_type.?);
                const s = std.heap.c_allocator.create(ThisAsyncState) catch {
                    @panic("bam");
                };

                const is_static = params.len == 0 or params[0].type != T;
                if (!is_static) {
                    var raw: ?*anyopaque = null;
                    if (c.napi_unwrap(env, this_arg, &raw) != c.napi_ok or raw == null) {
                        _ = c.napi_throw_error(env, null, "unwrap failed");
                        return null;
                    }
                    const self: *T = @ptrCast(@alignCast(raw.?));
                    s.*.params[0] = self.*;
                }

                const offset = if (is_static) 0 else 1;
                var arg: u8 = 0;

                // TODO: use this arena
                var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
                defer arena.deinit();

                inline for (params[offset..], offset..) |p, i| {
                    {
                        if (params[i].type.? == NodeContext) {
                            s.*.params[i] = node;
                        } else if (params[i].type.? == std.mem.Allocator) {
                            s.*.params[i] = std.heap.c_allocator;
                        } else {
                            // TODO: only serialized or wrapped values allowed in async
                            if (arg >= argc) {
                                node.throw(error.MissingArguments);
                                return null;
                            }
                            s.*.params[i] = node.deserialize(
                                p.type.?,
                                NodeValue{
                                    .napi_env = node.napi_env,
                                    .napi_value = args[arg],
                                },
                            ) catch |err| {
                                node.handleError(err);
                                return null;
                            };

                            // if (@hasDecl(p.type.?, "__is_node_function")) {
                            //     // TODO: make this async
                            // }

                            arg += 1;
                        }
                    }
                }

                const handler = opaque {
                    pub fn work(_: c.napi_env, data: ?*anyopaque) callconv(.c) void {
                        std.log.info("worker thread {any}", .{std.Thread.getCurrentId()});

                        var state: *ThisAsyncState = @ptrCast(@alignCast(data));

                        const res = @call(.auto, fun, state.*.params);

                        std.log.info("RETURN {any}", .{res});
                        state.return_value = res;
                    }

                    pub fn resolve(e: c.napi_env, _: c_uint, data: ?*anyopaque) callconv(.c) void {
                        const state: *ThisAsyncState = @ptrCast(@alignCast(data));
                        const n = NodeContext{ .napi_env = e };
                        std.log.info("DATA {any}", .{state});
                        std.log.info("completion thread {any}", .{std.Thread.getCurrentId()});

                        if (state.return_value) |v| {
                            const resolution: c.napi_value = (n.serialize(v) catch unreachable).napi_value;
                            // _ = c.napi_create_double(c_env, 12.23, &resolution);
                            const res = s2e(c.napi_resolve_deferred(e, state.deferred, resolution)) catch unreachable;
                            std.log.info("res {any}", .{res});
                        } else |err| {
                            std.log.debug("error {any}", .{err});
                            s2e(c.napi_reject_deferred(e, state.deferred, (n.serialize((err) catch unreachable)).napi_value)) catch unreachable;
                        }
                    }
                };

                var deferred: c.napi_deferred = undefined;
                var promise: c.napi_value = undefined;
                s2e(c.napi_create_promise(env, &deferred, &promise)) catch |err| {
                    node.handleError(err);
                    return null;
                };
                s.*.deferred = deferred;

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
                    node.handleError(err);
                    return null;
                };
                s2e(c.napi_queue_async_work(env, task)) catch |err| {
                    node.handleError(err);
                    return null;
                };

                return promise;
            }
        }.f;
    }

    pub fn serialize(self: Self, value: anytype) !NodeValue {
        return .{
            .napi_env = self.napi_env,
            .napi_value = try Convert.nodeFromNative(self.napi_env, value),
        };
    }

    pub fn deserialize(self: Self, comptime T: type, value: NodeValue) !T {
        return try Convert.nativeFromNode(self.napi_env, T, value.napi_value, std.heap.c_allocator);
    }

    pub fn handleError(self: Self, err: anyerror) void {
        lib.handleError(self.napi_env, err);
    }

    pub fn throw(self: Self, err: anyerror) void {
        _ = c.napi_throw_error(self.napi_env, @errorName(err), @errorName(err));
    }

    fn get(self: Self, f: anytype) !NodeValue {
        var res: c.napi_value = undefined;
        try s2e(f(self.napi_env, &res));
        return NodeValue{ .napi_env = self.napi_env, .napi_value = res };
    }
};

fn AsyncState(comptime params: []const std.builtin.Type.Fn.Param, comptime RET: anytype) type {
    return struct {
        deferred: c.napi_deferred,
        this: ?*anyopaque,
        params: TupleTypeOf(params),
        return_value: RET,
    };
}

fn TupleTypeOf(comptime params: []const std.builtin.Type.Fn.Param) type {
    comptime var argTypes: [params.len]type = undefined;
    inline for (0..params.len) |i| {
        argTypes[i] = params[i].type.?;
    }

    return std.meta.Tuple(&argTypes);
}

inline fn endsWith(comptime haystack: []const u8, comptime needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    const start = haystack.len - needle.len;
    return std.mem.eql(u8, haystack[start..], needle);
}

const SelfParamType = enum { none, value, pointer };

inline fn isSelfParam(comptime T: anytype, comptime param: std.builtin.Type.Fn.Param) SelfParamType {
    switch (@typeInfo(param.type.?)) {
        .pointer => |p| {
            if (p.child == T) return .pointer;
        },
        .@"struct" => {
            if (param.type == T) return .value;
        },
        else => {},
    }

    return .none;
}

inline fn getSelfParam(comptime T: anytype, comptime params: []const std.builtin.Type.Fn.Param) SelfParamType {
    if (params.len == 0) {
        return .none;
    }

    return isSelfParam(T, params[0]);
}

const ZigOrJsPointer = union(enum) {
    zig: ?*anyopaque,
    js: c.napi_value,
};

inline fn callFunction(
    comptime T: anytype,
    comptime fun: anytype,
    node: NodeContext,
    this: ZigOrJsPointer,
    js_args: []c.napi_value,
) !c.napi_value {
    const params = switch (@typeInfo(@TypeOf(fun))) {
        .@"fn" => |t| t.params,
        else => @compileError("`fun` must be a function."),
    };

    // TODO:
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    var fields: TupleTypeOf(params) = undefined;
    const selfParam = getSelfParam(T, params);

    if (selfParam != .none) {
        const ptr = switch (this) {
            .js => |v| js: {
                var raw: ?*anyopaque = null;
                if (c.napi_unwrap(node.napi_env, v, &raw) != c.napi_ok or raw == null) {
                    unreachable;
                }
                break :js raw;
            },
            .zig => |v| v,
        };

        if (ptr) |v| {
            const self: *T = @ptrCast(@alignCast(v));
            if (selfParam == .pointer) {
                fields[0] = self;
            } else {
                fields[0] = self.*;
            }
        } else {
            // TODO: method was called without rquired this
            unreachable;
        }
    }

    const offset = if (selfParam == .none) 0 else 1;
    var arg: u8 = 0;
    inline for (params[offset..], offset..) |p, i| {
        {
            if (params[i].type.? == NodeContext) {
                fields[i] = node;
            } else if (params[i].type.? == std.mem.Allocator) {
                fields[i] = std.heap.c_allocator;
            } else {
                if (arg >= js_args.len) {
                    return error.MissingArguments;
                }
                fields[i] = node.deserialize(
                    p.type.?,
                    NodeValue{
                        .napi_env = node.napi_env,
                        .napi_value = js_args[arg],
                    },
                ) catch |err| {
                    return err;
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
