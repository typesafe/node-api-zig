const std = @import("std");
const lib = @import("c.zig");
const c = lib.c;
const s2e = lib.statusToError;

const Self = @This();

napi_env: c.napi_env,

pub const NodeValueType = enum {
    Undefined,
    Null,
    Boolean,
    Number,
    String,
    Symbol,
    Object,
    Function,
    External,
    BigInt,
};

// napi_int8_array,
// napi_uint8_array,
// napi_uint8_clamped_array,
// napi_int16_array,
// napi_uint16_array,
// napi_int32_array,
// napi_uint32_array,
// napi_float32_array,
// napi_float64_array,
// napi_bigint64_array,
// napi_biguint64_array,

pub const NodeValue = struct {
    const Self = @This();

    napi_env: c.napi_env,
    napi_value: c.napi_value,

    pub fn typeof(self: NodeValue.Self) !NodeValueType {
        var result: c.napi_valuetype = undefined;
        try s2e(c.napi_typeof(self.napi_env, self.napi_env, &result));

        return switch (result) {
            c.napi_undefined => NodeValueType.Undefined,
            c.napi_null => NodeValueType.Null,
            c.napi_boolean => NodeValueType.Boolean,
            c.napi_number => NodeValueType.Number,
            c.napi_string => NodeValueType.String,
            c.napi_symbol => NodeValueType.Symbol,
            c.napi_object => NodeValueType.Object,
            c.napi_function => NodeValueType.Function,
            c.napi_external => NodeValueType.External,
            c.napi_bigint => NodeValueType.BigInt,
            else => return error.UnknownType,
        };
    }
};

pub fn serialize(self: Self, value: anytype) !c.napi_value {
    const T = @TypeOf(value);

    if (T == NodeValue) {
        return value.napi_value;
    }

    const info = @typeInfo(T);

    var res: c.napi_value = undefined;

    switch (info) {
        .null => try s2e(c.napi_get_null(self.napi_env, &res)),
        .undefined => try s2e(c.napi_get_undefined(self.napi_env, &res)),
        .bool => try s2e(c.napi_get_boolean(self.napi_env, value, &res)),
        .comptime_int => {
            try s2e(c.napi_create_int32(self.napi_env, value, &res));
        },
        .int => |i| {
            if (i.signedness == .signed) {
                try s2e(c.napi_create_int32(self.napi_env, value, &res));
            } else {
                try s2e(c.napi_create_uint32(self.napi_env, value, &res));
            }
        },
        .float, .comptime_float => try s2e(c.napi_create_double(self.napi_env, value, &res)),

        .@"enum" => |i| {
            // if enum has consistently named tags -> prefer tag name as string
            if (i.tag_type == u0 or i.is_exhaustive) {
                const name = @tagName(value);
                try s2e(c.napi_create_string_utf8(self.napi_env, name, name.len, &res));
            } else {
                try s2e(c.napi_get_value_int32(self.napi_env, @intFromEnum(value), &res));
            }
        },
        .optional => {
            if (value) |val| {
                return self.serialize(val);
            } else {
                try s2e(c.napi_get_null(self.napi_env, &res));
            }
        },
        .pointer => |p| {
            switch (p.size) {
                .one => {
                    return self.serialize(value.*);
                },
                .slice => {
                    if (p.child == u8 and p.is_const) {
                        try s2e(c.napi_create_string_utf8(self.napi_env, value.ptr, value.len, &res));
                    } else {
                        try s2e(c.napi_create_array_with_length(self.napi_env, value.len, &res));

                        for (value, 0..) |item, i| {
                            const el = try self.serialize(item);
                            try s2e(c.napi_set_element(self.napi_env, res, i, el));
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
                try s2e(c.napi_create_object(self.napi_env, &res));
                inline for (s.fields) |field| {
                    std.log.debug("tuple field: {any}", .{field});
                    if (field.type == void) continue;

                    const field_val = @field(value, field.name);

                    try s2e(c.napi_set_property(self.napi_env, res, try self.serialize(field.name), try self.serialize(field_val)));
                }
            } else {
                try s2e(c.napi_create_array_with_length(self.napi_env, s.fields.len, &res));
                inline for (s.fields, 0..) |field, i| {
                    std.log.debug("field: {any}", .{field});
                    if (field.type == void) continue;

                    const field_val = @field(value, field.name);
                    try s2e(c.napi_set_element(self.napi_env, res, i, try self.serialize(field_val)));
                }
            }
        },

        .array => |p| {
            if (p.child == u8) {
                try s2e(c.napi_create_string_utf8(self.napi_env, &value, value.len, &res));
            } else {
                try s2e(c.napi_create_array_with_length(self.napi_env, value.len, &res));

                for (value, 0..) |item, i| {
                    const el = try self.serialize(item);
                    try s2e(c.napi_set_element(self.napi_env, res, i, el));
                }
            }
        },
        .@"union" => |u| {
            if (u.tag_type) |Tag| {
                try s2e(c.napi_create_object(self.napi_env, &res));

                const tag = @as(Tag, value);
                const tag_name = @tagName(tag);
                try s2e(c.napi_set_property(self.napi_env, res, try self.serialize("type"), try self.serialize(tag_name)));

                inline for (u.fields) |f| {
                    if (std.mem.eql(u8, f.name, tag_name)) {
                        if (f.type == void) break;
                        try s2e(c.napi_set_property(self.napi_env, res, try self.serialize("value"), try self.serialize(@field(value, f.name))));
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

pub fn deserializeString(self: Self, value: c.napi_value, allocator: std.mem.Allocator) ![]const u8 {
    var len: usize = undefined;
    try s2e(c.napi_get_value_string_latin1(self.napi_env, value, null, 0, &len));
    const buf = try allocator.allocSentinel(u8, len, 0);
    try s2e(c.napi_get_value_string_latin1(self.napi_env, value, buf, len + 1, &len));
    return buf;
}

// pub fn deserializeStruct(self: Self, comptime T: type, value: c.napi_value, allocator: std.mem.Allocator) ![]const u8 {
//     const info = @typeInfo(T);
//     if (info.@"struct") |s| {
//         var result = allocator.create(T);
//         for (s.fields) |f| {
//             var v: c.napi_value = undefined;
//             try s2e(c.napi_get_property(self.napi_env, value, "", &v));
//             @field(result, f.name) = self.deserializeValue(f.type, v);
//         }
//         return result;
//     }
//     @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}. Please specify a struct.", .{@typeName(T)}));
// }

pub fn deserializeValue(self: Self, comptime T: type, value: c.napi_value) !T {
    const info = @typeInfo(T);

    var v: T = undefined;
    switch (info) {
        .bool => try s2e(c.napi_get_value_bool(self.napi_env, value, &v)),
        .int => |i| {
            if (i.signedness == .signed) {
                switch (i.bits) {
                    32 => try s2e(c.napi_get_value_int32(self.napi_env, value, &v)),
                    64 => try s2e(c.napi_get_value_int64(self.napi_env, value, &v)),
                    // 64 => .{ comptime_int, c.napi_get_value_int64 },
                    else => @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}", .{@typeName(T)})),
                }
            } else {
                switch (i.bits) {
                    // 32 => .{ comptime_int, c.napi_get_value_uint32 },
                    else => @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}", .{@typeName(T)})),
                }
            }
        },

        else => @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}", .{@typeName(T)})),
    }

    return v;

    // return switch (info) {
    //     .bool => {
    //         var b: bool = undefined;
    //         try s2e(c.napi_get_value_bool(self.napi_env, value, &b));
    //         return b;
    //     },
    //     .i32 => {
    //         var v: i32 = undefined;
    //         try s2e(c.napi_get_value_int32(self.napi_env, value, &v));
    //         return v;
    //     },
    //     .i64 => {
    //         var v: i64 = undefined;
    //         try s2e(c.napi_get_value_int64(self.napi_env, value, &v));
    //         return v;
    //     },

    //     else => @compileError(std.fmt.comptimePrint("Cannot deserialize value of type {s}", .{@typeName(T)})),
    // };
}
