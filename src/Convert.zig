const std = @import("std");
const lib = @import("c.zig");
const c = lib.c;
const s2e = lib.statusToError;
const node_values = @import("node_values.zig");
const NodeContext = @import("Node.zig").NodeContext;
const NodeValue = node_values.NodeValue;
const NodeObject = node_values.NodeObject;
const NodeArray = node_values.NodeArray;
const NodeFunction = node_values.NodeFunction;
const registry = @import("references.zig").Registry;

/// Converts a Zig value to a Node-API value. Memory for the node value is allocated by V8.
pub fn nodeFromNative(env: c.napi_env, value: anytype) !c.napi_value {
    const T = @TypeOf(value);

    const node = NodeContext.init(env);
    var res: c.napi_value = undefined;

    switch (@typeInfo(T)) {
        .type => return (try node.defineClass(value)).napi_value,
        .@"fn" => return (try node.defineFunction(value)).napi_value,
        .null => try s2e(c.napi_get_null(env, &res)),
        .void, .undefined => try s2e(c.napi_get_undefined(env, &res)),
        .bool => try s2e(c.napi_get_boolean(env, value, &res)),
        .comptime_int => {
            // comptime_int has no `signedness` or `bits`
            if (value < 0) {
                switch (@bitSizeOf(T)) {
                    0...32 => try s2e(c.napi_create_int32(env, value, &res)),
                    33...64 => try s2e(c.napi_create_int64(env, value, &res)),
                    else => |s| @compileError(std.fmt.comptimePrint("Cannot convert value of type '{s}', unsupported bitsize {d}", .{ @typeName(T), s })),
                }
            } else {
                switch (@bitSizeOf(T)) {
                    0...32 => try s2e(c.napi_create_uint32(env, value, &res)),
                    33...64 => try s2e(c.napi_create_bigint_uint64(env, value, &res)),
                    else => |s| @compileError(std.fmt.comptimePrint("Cannot convert value of type '{s}', unsupported bitsize {d}", .{ @typeName(T), s })),
                }
            }
        },
        .int => |i| {
            if (i.signedness == .signed) {
                switch (i.bits) {
                    32 => try s2e(c.napi_create_int32(env, value, &res)),
                    64 => try s2e(c.napi_create_int64(env, value, &res)),
                    else => |s| @compileError(std.fmt.comptimePrint("Cannot convert value of type '{s}', unsupported bitsize {d}", .{ @typeName(T), s })),
                }
            } else {
                switch (i.bits) {
                    32 => try s2e(c.napi_create_uint32(env, value, &res)),
                    64 => try s2e(c.napi_create_bigint_uint64(env, value, &res)),
                    else => |s| @compileError(std.fmt.comptimePrint("Cannot convert value of type '{s}', unsupported bitsize {d}", .{ @typeName(T), s })),
                }
            }
        },
        .float, .comptime_float => try s2e(c.napi_create_double(env, value, &res)),
        .enum_literal => {
            const name = @tagName(value);
            try s2e(c.napi_create_string_utf8(env, name, name.len, &res));
        },
        .@"enum" => |i| {
            // if enum has consistently named tags -> prefer tag name as string
            if (i.tag_type == u0 or i.is_exhaustive) {
                const name = @tagName(value);
                try s2e(c.napi_create_string_utf8(env, name, name.len, &res));
            } else {
                try s2e(c.napi_get_value_int32(env, @intFromEnum(value), &res));
            }
        },
        .optional => {
            if (value) |val| {
                return nodeFromNative(env, val);
            } else {
                try s2e(c.napi_get_null(env, &res));
            }
        },
        .pointer => |p| {
            switch (p.size) {
                .one => {
                    if (registry.get(@ptrCast(@constCast(value)))) |v| {
                        return v;
                    }

                    return nodeFromNative(env, value.*);
                },
                .slice => {
                    std.log.debug("serializing {s} of type {s}", .{ value, @typeName(T) });
                    if (p.child == u8) {
                        try s2e(c.napi_create_string_utf8(env, value.ptr, value.len, &res));
                    } else {
                        try s2e(c.napi_create_array_with_length(env, value.len, &res));

                        for (value, 0..) |item, i| {
                            const el = try nodeFromNative(env, item);
                            try s2e(c.napi_set_element(env, res, i, el));
                        }
                    }
                },
                .many => {
                    std.log.debug("serializing {s} of type {s}", .{ value, @typeName(T) });
                    if (p.child == u8) {
                        try s2e(c.napi_create_string_utf8(env, value, std.mem.len(value), &res));
                    } else {
                        @compileError(std.fmt.comptimePrint("Cannot convert node value to '{s}', Cannot convert c-style pointer values, they are not supported.", .{@typeName(T)}));
                    }
                },
                .c => {
                    // @compileError("Cannot convert c-style pointer values, they are not supported.");
                    @compileError(std.fmt.comptimePrint("Cannot convert node value to '{s}', Cannot convert c-style pointer values, they are not supported.", .{@typeName(T)}));
                },
            }
        },
        .@"struct" => |s| {
            if (T == NodeValue or T == NodeObject or T == NodeArray) {
                return value.napi_value;
            }

            if (!s.is_tuple) {
                try s2e(c.napi_create_object(env, &res));
                inline for (s.fields) |field| {
                    if (field.type == void) continue;

                    const field_val = @field(value, field.name);

                    try s2e(c.napi_set_property(env, res, try nodeFromNative(env, field.name), try nodeFromNative(env, field_val)));
                }
            } else {
                try s2e(c.napi_create_array_with_length(env, s.fields.len, &res));
                inline for (s.fields, 0..) |field, i| {
                    if (field.type == void) continue;

                    const field_val = @field(value, field.name);
                    try s2e(c.napi_set_element(env, res, i, try nodeFromNative(env, field_val)));
                }
            }
        },

        .array => |p| {
            if (p.child == u8) {
                try s2e(c.napi_create_string_utf8(env, &value, value.len, &res));
            } else {
                try s2e(c.napi_create_array_with_length(env, value.len, &res));

                for (value, 0..) |item, i| {
                    const el = try nodeFromNative(env, item);
                    try s2e(c.napi_set_element(env, res, i, el));
                }
            }
        },
        .@"union" => |u| {
            if (u.tag_type) |Tag| {
                try s2e(c.napi_create_object(env, &res));

                const tag = @as(Tag, value);
                const tag_name = @tagName(tag);
                try s2e(c.napi_set_property(env, res, try nodeFromNative(env, "type"), try nodeFromNative(env, tag_name)));

                inline for (u.fields) |f| {
                    if (std.mem.eql(u8, f.name, tag_name)) {
                        if (f.type == void) break;
                        try s2e(c.napi_set_property(env, res, try nodeFromNative(env, "value"), try nodeFromNative(env, @field(value, f.name))));
                        break;
                    }
                }
            } else {
                @compileError(std.fmt.comptimePrint("Cannot convert value of type '{s}', untagged unions are not supported.", .{@typeName(T)}));
            }
        },
        else => @compileError(std.fmt.comptimePrint("Cannot convert value of type '{s}'", .{@typeName(T)})),
    }

    return res;
}

/// Converts a Node-API value to a native Zig value.
pub fn nativeFromNode(env: c.napi_env, comptime T: type, js_value: c.napi_value, allocator: std.mem.Allocator) !T {
    var res: T = undefined;

    switch (@typeInfo(T)) {
        .bool => try s2e(c.napi_get_value_bool(env, js_value, &res)),
        .int => |i| {
            if (i.signedness == .signed) {
                switch (i.bits) {
                    32 => try s2e(c.napi_get_value_int32(env, js_value, &res)),
                    64 => try s2e(c.napi_get_value_int64(env, js_value, &res)),
                    else => @compileError(std.fmt.comptimePrint("Cannot convert node value to '{s}'", .{@typeName(T)})),
                }
            } else {
                switch (i.bits) {
                    32 => try s2e(c.napi_get_value_uint32(env, js_value, &res)),
                    64 => {
                        var b: bool = undefined;
                        try s2e(c.napi_get_value_bigint_uint64(env, js_value, &res, &b));
                    },
                    else => @compileError(std.fmt.comptimePrint("Cannot convert node value to '{s}'", .{@typeName(T)})),
                }
            }
        },
        .float => {
            var tmp: f64 = undefined;
            try s2e(c.napi_get_value_double(env, js_value, &tmp));
            res = @floatCast(tmp);
        },
        .@"enum" => |i| {
            // if enum has consistently named tags -> prefer tag name as string
            if (i.tag_type == u0 or i.is_exhaustive) {
                var len: usize = 0;
                const buf: [128]u8 = undefined;
                try s2e(c.napi_get_value_string_utf8(env, js_value, &buf, 128, &len));

                std.meta.stringToEnum(T, buf[0..len]);
            } else {
                var tmp: i32 = undefined;
                try s2e(c.napi_get_value_int32(env, js_value, &tmp));
                return @enumFromInt(tmp);
            }
        },
        .optional => |o| {
            var t: c.napi_valuetype = undefined;
            try s2e(c.napi_typeof(env, js_value, &t));
            switch (t) {
                c.napi_undefined, c.napi_null => return null,
                else => return try nativeFromNode(env, o.child, js_value, allocator),
            }
        },
        .pointer => |p| {
            switch (p.size) {
                .one => {
                    // pointers are considered wrapped
                    try s2e(c.napi_unwrap(env, js_value, @as([*c]?*anyopaque, @ptrCast(&res))));
                },
                .slice => {
                    switch (p.child) {
                        u8 => {
                            var len: usize = undefined;
                            try s2e(c.napi_get_value_string_utf8(env, js_value, null, 0, &len));
                            const buf = try std.heap.c_allocator.allocSentinel(u8, len, 0);
                            try s2e(c.napi_get_value_string_utf8(env, js_value, buf, len + 1, &len));
                            return buf;
                        },
                        else => {
                            var len: usize = undefined;
                            try s2e(c.napi_get_array_length(env, js_value, &len));
                            if (len > 0) {
                                const buf = try std.heap.c_allocator.allocSentinel(T, len, 0);

                                for (0..len) |i| {
                                    var elem: c.napi_value = undefined;
                                    try s2e(c.napi_get_element(env, js_value, i, &elem));
                                    buf[i] = try nativeFromNode(env, p.child, elem, allocator);
                                }

                                return buf;
                            } else {
                                return [0]T;
                            }
                        },
                    }
                },
                else => {
                    @compileError("Cannot convert c-style pointer values, they are not supported.");
                },
            }
        },
        .@"struct" => |s| {
            if (T == NodeValue or T == NodeObject or T == NodeArray) {
                return T{ .napi_env = env, .napi_value = js_value };
            }
            if (@hasDecl(T, "__is_node_function")) {
                return T{ .napi_env = env, .napi_value = js_value };
            }

            var instance: T = undefined;
            inline for (s.fields) |field| {
                var v: c.napi_value = undefined;
                try s2e(c.napi_get_named_property(env, js_value, field.name.ptr, &v));
                @field(instance, field.name) = try nativeFromNode(env, field.type, v, allocator);
            }

            return instance;
        },

        else => @compileError(std.fmt.comptimePrint("Cannot convert node value to '{s}'", .{@typeName(T)})),
    }

    return res;
}
