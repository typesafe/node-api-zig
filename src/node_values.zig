const std = @import("std");
const lib = @import("c.zig");
const c = lib.c;
const s2e = lib.statusToError;

const Convert = @import("Convert.zig");

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

// TODO: use napi_create_reference to support NodeValue.reference()?

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

    pub fn init(env: c.napi_env, value: c.napi_value) Self {
        return .{ .napi_env = env, .napi_value = value };
    }

    pub fn typeof(self: NodeValue.Self) !NodeValueType {
        var result: c.napi_valuetype = undefined;
        try s2e(c.napi_typeof(self.napi_env, self.napi_value, &result));

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

    /// Casts the value to an NodeObject. Fails is the typeof != .Object.
    pub fn asObject(self: NodeValue.Self) !NodeObject {
        if (self.typeof() == .Object) {
            return NodeObject{
                .napi_env = self.napi_env,
                .napi_value = self.napi_value,
            };
        }

        return error.NodeValueIsNoObject;
    }

    /// Casts the value to an NodeArray. Fails is the typeof != .Array.
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

    fn is(self: NodeValue.Self, is_fn: anytype) !bool {
        var b: bool = undefined;
        s2e(is_fn(self.napi_env, self.napi_value, &b));
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

    /// Gets the value of a property.
    pub fn get(self: NodeObject.Self, property_name: []const u8) !NodeValue {
        var v: c.napi_value = undefined;
        try s2e(c.napi_get_named_property(self.napi_env, self.napi_value, property_name.ptr, &v));
        return NodeValue{ .napi_env = self.napi_env, .napi_value = v };
    }

    /// Sets the value of a property.
    pub fn set(self: NodeObject.Self, property_name: []const u8, value: NodeValue) !NodeValue {
        try s2e(c.napi_set_named_property(self.napi_env, self.napi_value, property_name.ptr, value.napi_value));
        return value;
    }

    /// Gets a NodeValue indicating wether the object has a property with the specified name.
    pub fn has(self: NodeObject.Self, property_name: []const u8) !bool {
        var v: bool = undefined;
        try s2e(c.napi_has_named_property(self.napi_env, self.napi_value, property_name.ptr, &v));
        return v;
    }

    /// Gets a NodeValue indicating wether the object has the named own property. key must be a string or a symbol, or an error will be thrown.
    pub fn hasOwn(self: NodeObject.Self, property_name: []const u8) !bool {
        var v: bool = undefined;
        try s2e(c.napi_has_own_property(self.napi_env, self.napi_value, try Convert.nodeFromNative(self.napi_env, property_name), &v));
        return v;
    }
    /// Gets the value of a property.
    pub fn delete(self: NodeObject.Self, property_name: []const u8) !bool {
        var v: bool = undefined;
        try s2e(c.napi_delete_property(
            self.napi_env,
            self.napi_value,
            try Convert.nodeFromNative(self.napi_env, property_name),
            &v,
        ));
        return v;
    }

    /// Returns the names of the enumerable properties as a NodeArray of strings. Symbol keys will not be included.
    pub fn getPropertyNames(self: NodeObject.Self) !NodeArray {
        var v: c.napi_value = undefined;
        try s2e(c.napi_get_property_names(self.napi_env, self.napi_value, &v));
        return NodeArray{ .napi_env = self.napi_env, .napi_value = v };
    }
};

/// Represents a JS function.
pub fn NodeFunction(comptime F: anytype) type {
    const f = switch (@typeInfo(F)) {
        .@"fn" => |info| info,
        else => @compileError("F must be function"),
    };

    return struct {
        const Self = @This();
        pub const __is_node_function = true;

        napi_env: c.napi_env,
        napi_value: c.napi_value,

        pub fn call(self: Self, args: TupleTypeOf(f.params)) !f.return_type.? {
            var js_args: [f.params.len]c.napi_value = undefined;
            inline for (0..args.len) |i| {
                js_args[i] = try Convert.nodeFromNative(self.napi_env, args[i]);
            }
            var res: c.napi_value = undefined;

            var global: c.napi_value = undefined;
            _ = c.napi_get_global(self.napi_env, &global);

            try s2e(c.napi_call_function(self.napi_env, global, self.napi_value, js_args.len, &js_args, &res));

            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();

            return try Convert.nativeFromNode(self.napi_env, f.return_type.?, res, arena.allocator());
        }
    };
}

fn TupleTypeOf(params: []const std.builtin.Type.Fn.Param) type {
    comptime var argTypes: [params.len]type = undefined;
    inline for (0..params.len) |i| {
        argTypes[i] = params[i].type.?;
    }

    return std.meta.Tuple(&argTypes);
}
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

    // get/set [], push, splice, etc.
};
