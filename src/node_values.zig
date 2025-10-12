const std = @import("std");
const lib = @import("c.zig");
const c = lib.c;
const s2e = lib.statusToError;

const Serializer = @import("Serializer.zig");

// https://nodejs.org/api/n-api.html#napi_valuetype
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

/// Represents a JS value.
pub const NodeValue = struct {
    const Self = @This();

    napi_env: c.napi_env,
    napi_value: c.napi_value,

    pub fn deserializeValue(self: NodeValue.Self, comptime T: type) !T {
        return Serializer.deserializeValue(self.napi_env, T, self.napi_value);
    }

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

    pub fn asDateValue(self: NodeValue.Self) !f64 {
        var v: f64 = undefined;
        s2e(c.napi_get_date_value(self.napi_env, self.napi_value, &v));
        return v;
    }

    pub fn asObject(self: NodeValue.Self) !NodeObject {
        if (self.typeof() == .Object) {
            return NodeObject{
                .napi_env = self.napi_env,
                .napi_value = self.napi_value,
            };
        }

        return error.NodeValueIsNoObject;
    }

    pub fn asArray(self: NodeValue.Self) !NodeArray {
        if (self.typeof() == .Object) {
            return NodeObject{
                .napi_env = self.napi_env,
                .napi_value = self.napi_value,
            };
        }

        return error.NodeValueIsNoObject;
    }

    pub fn isArray(self: NodeValue.Self) !bool {
        return self.is(c.napi_is_array);
    }

    pub fn isTypedArray(self: NodeValue.Self) !bool {
        return self.is(c.napi_is_typedarray);
    }

    pub fn isArrayBuffer(self: NodeValue.Self) !bool {
        return self.is(c.napi_is_arraybuffer);
    }

    pub fn isBuffer(self: NodeValue.Self) !bool {
        return self.is(c.napi_is_buffer);
    }

    pub fn isDataView(self: NodeValue.Self) !bool {
        return self.is(c.napi_is_dataview);
    }

    pub fn isDate(self: NodeValue.Self) !bool {
        return self.is(c.napi_is_date);
    }

    pub fn isError(self: NodeValue.Self) !bool {
        return self.is(c.napi_is_error);
    }

    pub fn isPromise(self: NodeValue.Self) !bool {
        return self.is(c.napi_is_promise);
    }

    fn is(self: NodeValue.Self, f: anytype) !bool {
        var b: bool = undefined;
        s2e(f(self.napi_env, self.napi_value, &b));
        return b;
    }
};

/// Represents a JS Object, can be used to process JS objects by reference.
pub const NodeObject = struct {
    const Self = @This();

    napi_env: c.napi_env,
    napi_value: c.napi_value,

    pub fn asValue(self: NodeObject.Self) !NodeValue {
        return NodeValue{
            .napi_env = self.napi_env,
            .napi_value = self.napi_value,
        };
    }
};

pub const NodeArray = struct {
    const Self = @This();

    napi_env: c.napi_env,
    napi_value: c.napi_value,

    fn len(self: NodeValue.Self) !u32 {
        var v: u32 = undefined;
        s2e(c.napi_get_array_length(self.napi_env, self.napi_value, &v));
        return v;
    }

    pub fn asValue(self: NodeArray.Self) !NodeValue {
        return NodeValue{
            .napi_env = self.napi_env,
            .napi_value = self.napi_value,
        };
    }
};
