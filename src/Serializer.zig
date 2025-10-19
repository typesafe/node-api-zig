const std = @import("std");
const lib = @import("c.zig");
const c = lib.c;
const s2e = lib.statusToError;
const NodeValue = @import("node_values.zig").NodeValue;
const NodeObject = @import("node_values.zig").NodeObject;

/// Converts a Zig value to a Node-API value.
pub fn serialize(env: c.napi_env, value: anytype) !c.napi_value {
    const T = @TypeOf(value);

    // TODO: complete
    if (T == NodeValue or T == NodeObject) {
        return value.napi_value;
    }

    const info = @typeInfo(T);

    var res: c.napi_value = undefined;

    switch (info) {
        .null => try s2e(c.napi_get_null(env, &res)),
        .void, .undefined => try s2e(c.napi_get_undefined(env, &res)),
        .bool => try s2e(c.napi_get_boolean(env, value, &res)),
        .comptime_int => {
            if (value < 0) {
                switch (@bitSizeOf(T)) {
                    0...32 => {
                        try s2e(c.napi_create_int32(env, value, &res));
                    },
                    33...64 => {
                        try s2e(c.napi_create_int64(env, value, &res));
                    },
                    else => |s| @compileError(std.fmt.comptimePrint("Cannot serialize value of type {s}, unsupported bitsize", .{ @typeName(T), s })),
                }
                try s2e(c.napi_create_int32(env, value, &res));
            } else {
                switch (@bitSizeOf(T)) {
                    0...32 => {
                        try s2e(c.napi_create_uint32(env, value, &res));
                    }, //
                    else => {
                        try s2e(c.napi_create_bigint_uint64(env, value, &res));
                    },
                    // else => @compileError(std.fmt.comptimePrint("Cannot serialize value of type {s}, unsupported bitsize {any}", .{ @typeName(T), @bitSizeOf(T) })),
                }
            }
        },
        .int => |i| {
            if (i.signedness == .signed) {
                try s2e(c.napi_create_int32(env, value, &res));
            } else {
                switch (i.bits) {
                    33...64 => try s2e(c.napi_create_bigint_uint64(env, value, &res)),
                    else => try s2e(c.napi_create_uint32(env, value, &res)),
                }
            }
        },
        .float, .comptime_float => try s2e(c.napi_create_double(env, value, &res)),

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
                    return serialize(env, value.*);
                },
                .slice => {
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
                    @compileError("C/Many pointers are not supported.");
                },
            }
        },
        .@"struct" => |s| {
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
                @compileError("Untagged unions are not supported for JSON serialization.");
            }
        },

        else => @compileError(std.fmt.comptimePrint("Cannot serialize value of type {s}", .{@typeName(T)})),
    }

    return res;
}

// pub fn deserializeString(env: c.napi_env, value: c.napi_value, allocator: std.mem.Allocator) ![]u8 {
//     var len: usize = undefined;
//     try s2e(c.napi_get_value_string_latin1(env, value, null, 0, &len));
//     const buf = try std.heap.c_allocator.allocSentinel(u8, len, 0);
//     try s2e(c.napi_get_value_string_latin1(env, value, buf, len + 1, &len));
//     return buf;
// }

// pub fn deserializeStruct(self: Self, comptime T: type, value: c.napi_value, allocator: std.mem.Allocator) ![]const u8 {
//     const info = @typeInfo(T);
//     if (info.@"struct") |s| {
//         var result = allocator.create(T);
//         for (s.fields) |f| {
//             var v: c.napi_value = undefined;
//             try s2e(c.napi_get_property(env, value, "", &v));
//             @field(result, f.name) = self.deserializeValue(f.type, v);
//         }
//         return result;
//     }
//     @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}. Please specify a struct.", .{@typeName(T)}));
// }

/// Converts scalar JS values to Zig values.
pub fn deserialize(env: c.napi_env, comptime T: type, value: c.napi_value, allocator: std.mem.Allocator) !T {
    const info = @typeInfo(T);

    var v: T = undefined;
    switch (info) {
        .float => {
            var tmp: f64 = undefined;
            try s2e(c.napi_get_value_double(env, value, &tmp));
            v = @floatCast(tmp);
        },
        .bool => try s2e(c.napi_get_value_bool(env, value, &v)),
        .int => |i| {
            if (i.signedness == .signed) {
                switch (i.bits) {
                    32 => try s2e(c.napi_get_value_int32(env, value, &v)),
                    64 => try s2e(c.napi_get_value_int64(env, value, &v)),
                    // 64 => .{ comptime_int, c.napi_get_value_int64 },
                    else => @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}", .{@typeName(T)})),
                }
            } else {
                switch (i.bits) {
                    1...64 => {
                        var tmp: u32 = undefined;
                        try s2e(c.napi_get_value_uint32(env, value, &tmp));
                        return @intCast(tmp);
                    },

                    // 32 => .{ comptime_int, c.napi_get_value_uint32 },
                    else => @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}", .{@typeName(T)})),
                }
            }
        },
        .optional => |o| {
            v = try deserialize(env, o.child, value, allocator);
        },
        .pointer => |p| {
            switch (p.size) {
                .one => {
                    // pointers are considered wrapped
                    try s2e(c.napi_unwrap(env, value, @as([*c]?*anyopaque, @ptrCast(&v))));
                },
                .slice => {
                    switch (p.child) {
                        u8 => {
                            var len: usize = undefined;
                            try s2e(c.napi_get_value_string_utf8(env, value, null, 0, &len));
                            const buf = try std.heap.c_allocator.allocSentinel(u8, len, 0);
                            try s2e(c.napi_get_value_string_utf8(env, value, buf, len + 1, &len));
                            return buf;
                        },
                        else => {
                            @compileError("only u8 slices");
                        },
                    }
                },
                else => {
                    @compileError("one or slice pointers");
                },
            }
        },
        .@"struct" => {
            if (T == NodeValue) {
                return NodeValue{ .napi_env = env, .napi_value = value };
            }
        },
        else => @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}", .{@typeName(T)})),
    }

    return v;

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
