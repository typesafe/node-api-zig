const std = @import("std");
const lib = @import("c.zig");
const c = lib.c;
const s2e = lib.statusToError;
const node_values = @import("node_values.zig");

const NodeValue = node_values.NodeValue;
const NodeObject = node_values.NodeObject;
const NodeArray = node_values.NodeArray;
const NodeFunction = node_values.NodeFunction;

/// Converts a Zig value to a Node-API value. Memory for the node value is allocated by V8.
pub fn serialize(env: c.napi_env, value: anytype) !c.napi_value {
    const T = @TypeOf(value);

    var res: c.napi_value = undefined;

    switch (@typeInfo(T)) {
        .null => try s2e(c.napi_get_null(env, &res)),
        .void, .undefined => try s2e(c.napi_get_undefined(env, &res)),
        .bool => try s2e(c.napi_get_boolean(env, value, &res)),
        .comptime_int => {
            // comptime_int has no `signedness` or `bits`
            if (value < 0) {
                switch (@bitSizeOf(T)) {
                    0...32 => try s2e(c.napi_create_int32(env, value, &res)),
                    33...64 => try s2e(c.napi_create_int64(env, value, &res)),
                    else => |s| @compileError(std.fmt.comptimePrint("Cannot serialize value of type {s}, unsupported bitsize {d}", .{ @typeName(T), s })),
                }
            } else {
                switch (@bitSizeOf(T)) {
                    0...32 => try s2e(c.napi_create_uint32(env, value, &res)),
                    33...64 => try s2e(c.napi_create_bigint_uint64(env, value, &res)),
                    else => |s| @compileError(std.fmt.comptimePrint("Cannot serialize value of type {s}, unsupported bitsize {d}", .{ @typeName(T), s })),
                }
            }
        },
        .int => |i| {
            if (i.signedness == .signed) {
                switch (i.bits) {
                    0...32 => try s2e(c.napi_create_int32(env, value, &res)),
                    33...64 => try s2e(c.napi_create_int64(env, value, &res)),
                    else => |s| @compileError(std.fmt.comptimePrint("Cannot serialize value of type {s}, unsupported bitsize {d}", .{ @typeName(T), s })),
                }
            } else {
                switch (i.bits) {
                    0...32 => try s2e(c.napi_create_uint32(env, value, &res)),
                    33...64 => try s2e(c.napi_create_bigint_uint64(env, value, &res)),
                    else => |s| @compileError(std.fmt.comptimePrint("Cannot serialize value of type {s}, unsupported bitsize {d}", .{ @typeName(T), s })),
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
                return serialize(env, val);
            } else {
                try s2e(c.napi_get_null(env, &res));
            }
        },
        .pointer => |p| {
            switch (p.size) {
                .one => {
                    // TODO: could be wrapped value, do we need this?
                    // how do we know if the instance was already wrapped before?
                    // hashset?

                    return serialize(env, value.*);
                },
                .slice => {
                    std.log.debug("serializing {s} of type {s}", .{ value, @typeName(T) });
                    if (p.child == u8) {
                        try s2e(c.napi_create_string_utf8(env, value.ptr, value.len, &res));
                    } else {
                        try s2e(c.napi_create_array_with_length(env, value.len, &res));

                        for (value, 0..) |item, i| {
                            const el = try serialize(env, item);
                            try s2e(c.napi_set_element(env, res, i, el));
                        }
                    }
                },
                .many, .c => {
                    @compileError("Cannot serialize c-style pointer values, they are not supported.");
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
                    // std.log.debug("tuple field: {any}", .{field});
                    if (field.type == void) continue;

                    const field_val = @field(value, field.name);

                    try s2e(c.napi_set_property(env, res, try serialize(env, field.name), try serialize(env, field_val)));
                }
            } else {
                try s2e(c.napi_create_array_with_length(env, s.fields.len, &res));
                inline for (s.fields, 0..) |field, i| {
                    // std.log.debug("field: {any}", .{field});
                    if (field.type == void) continue;

                    const field_val = @field(value, field.name);
                    try s2e(c.napi_set_element(env, res, i, try serialize(env, field_val)));
                }
            }
        },

        .array => |p| {
            if (p.child == u8) {
                try s2e(c.napi_create_string_utf8(env, &value, value.len, &res));
            } else {
                try s2e(c.napi_create_array_with_length(env, value.len, &res));

                for (value, 0..) |item, i| {
                    const el = try serialize(env, item);
                    try s2e(c.napi_set_element(env, res, i, el));
                }
            }
        },
        .vector => |p| {
            if (p.child == u8) {
                try s2e(c.napi_create_string_utf8(env, &value, value.len, &res));
            } else {
                try s2e(c.napi_create_array_with_length(env, value.len, &res));

                for (value, 0..) |item, i| {
                    const el = try serialize(env, item);
                    try s2e(c.napi_set_element(env, res, i, el));
                }
            }
        },
        .@"union" => |u| {
            if (u.tag_type) |Tag| {
                try s2e(c.napi_create_object(env, &res));

                const tag = @as(Tag, value);
                const tag_name = @tagName(tag);
                try s2e(c.napi_set_property(env, res, try serialize(env, "type"), try serialize(env, tag_name)));

                inline for (u.fields) |f| {
                    if (std.mem.eql(u8, f.name, tag_name)) {
                        if (f.type == void) break;
                        try s2e(c.napi_set_property(env, res, try serialize(env, "value"), try serialize(env, @field(value, f.name))));
                        break;
                    }
                }
            } else {
                @compileError(std.fmt.comptimePrint("Cannot serialize value of type {s}, untagged unions are not supported.", .{@typeName(T)}));
            }
        },

        else => @compileError(std.fmt.comptimePrint("Cannot serialize value of type {s}", .{@typeName(T)})),
    }

    return res;
}

/// Converts a Node-API value to a native Zig value.
pub fn deserialize(env: c.napi_env, comptime T: type, js_value: c.napi_value, allocator: std.mem.Allocator) !T {
    var res: T = undefined;

    switch (@typeInfo(T)) {
        .bool => try s2e(c.napi_get_value_bool(env, js_value, &res)),
        .int => |i| {
            if (i.signedness == .signed) {
                switch (i.bits) {
                    0...32 => try s2e(c.napi_get_value_int32(env, js_value, &res)),
                    33...64 => try s2e(c.napi_get_value_int64(env, js_value, &res)),
                    else => @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}", .{@typeName(T)})),
                }
            } else {
                switch (i.bits) {
                    0...32 => {
                        var tmp: u32 = undefined;
                        try s2e(c.napi_get_value_uint32(env, js_value, &tmp));
                        return @intCast(tmp);
                    },
                    33...64 => {
                        var tmp: u64 = undefined;
                        var b: bool = undefined;
                        try s2e(c.napi_get_value_bigint_uint64(env, js_value, &tmp, &b));
                        return @intCast(tmp);
                    },
                    else => @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}", .{@typeName(T)})),
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
                else => return try deserialize(env, o.child, js_value, allocator),
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
                                    buf[i] = try deserialize(env, p.child, elem, allocator);
                                }

                                return buf;
                            } else {
                                return [0]T;
                            }
                        },
                    }
                },
                else => {
                    @compileError("Cannot serialize c-style pointer values, they are not supported.");
                },
            }
        },
        .@"struct" => {
            if (T == NodeValue) {
                return T{ .napi_env = env, .napi_value = js_value };
            }
            if (@hasDecl(T, "__is_node_function")) {
                return T{ .napi_env = env, .napi_value = js_value };
            }

            // TODO
        },

        else => @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}", .{@typeName(T)})),
    }

    return res;

    // return switch (info) {
    //     .bool => {
    //         var b: bool = undefined;
    //         try s2e(c.napi_get_value_bool(env, value, &b));
    //         return b;
    //     },
    //     .i32 => {
    //         var v: i32 = undefined;
    //         try s2e(c.napi_get_value_int32(env, value, &v));
    //         return v;
    //     },
    //     .i64 => {
    //         var v: i64 = undefined;
    //         try s2e(c.napi_get_value_int64(env, value, &v));
    //         return v;
    //     },

    //     else => @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}", .{@typeName(T)})),
    // };
}

// fn wrapCallback(comptime T: anytype, callback: NodeFunction) T {
//     const fn_type = (@typeInfo(T).pointer.child);
//     const info = @typeInfo(fn_type).@"fn";
//     const params = info.params;

//     // const fns = wrapCallback(T, callback);
//     return switch (params.len) {
//         0 => opaque {
//             inline fn cb0() info.return_type.? {
//                 return callback.call(.{});
//             }
//             inline fn cb1(arg1: info.params[0].type.?) info.return_type.? {
//                 return callback.call(.{arg1});
//             }
//         }.cb0,
//         1 => opaque {
//             inline fn cb0() info.return_type.? {
//                 return callback.call(.{});
//             }
//             inline fn cb1(arg1: info.params[0].type.?) info.return_type.? {
//                 return callback.call(.{arg1});
//             }
//         }.cb1,
//         else => @compileError("too many arguments"),
//     };
// }

// fn CallbackWrapper(comptime info: std.builtin.Type.Fn, cb: NodeValue) type {
//     return opaque {
//         pub fn cb0() info.return_type.? {
//             return cb.call(.{});
//         }
//         pub fn cb1(arg1: info.params[0].type.?) info.return_type.? {
//             return cb.call(.{arg1});
//         }
//     };
// }
