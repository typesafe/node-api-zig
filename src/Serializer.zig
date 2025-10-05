const std = @import("std");
const lib = @import("c.zig");
const c = lib.c;
const NodeApiError = lib.NodeApiError;
const s2e = lib.statusToError;

const Self = @This();

napi_env: c.napi_env,

pub const NodeValue = struct {
    napi_env: c.napi_env,
    napi_value: c.napi_value,
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
        .optional => |o| {
            if (o) |v| {
                return self.serialize(v);
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
