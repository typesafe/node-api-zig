const std = @import("std");
const c = @import("c.zig").c;

/// Represents a context that the underlying Node-API implementation can use to persist VM-specific state.
pub const NodeContext = struct {
    const Self = @This();

    napi_env: c.napi_env,

    pub fn throwError(self: Self, msg: []const u8) !void {
        var err: c.napi_value = undefined;
        _ = c.napi_create_error(self.napi_env, null, (try self.createString(msg)).napi_value, &err);
        _ = c.napi_throw(self.napi_env, err);
    }

    pub fn createString(self: Self, value: []const u8) !NodeValue {
        var str: c.napi_value = undefined;
        _ = c.napi_create_string_latin1(self.napi_env, value.ptr, value.len, &str);
        return .{ .napi_env = self.napi_env, .napi_value = str };
    }

    // https://nodejs.org/api/n-api.html#error-handling
    fn handleNapiReturnCode(value: c_uint) !void {
        if (value == c.napi_ok) {
            return;
        }
    }
};

pub const NodeObject = struct {
    napi_env: c.napi_env,
    napi_value: c.napi_value,
};

pub const NodeString = struct {
    napi_env: c.napi_env,
    napi_value: c.napi_value,
};

pub const NodeValue = struct {
    napi_env: c.napi_env,
    napi_value: c.napi_value,
};
