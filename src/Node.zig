const std = @import("std");
const lib = @import("c.zig");
const Serializer = @import("Serializer.zig");

const c = lib.c;
const NodeApiError = lib.NodeApiError;
const s2e = lib.statusToError;

/// Represents a context that the underlying Node-API implementation can use to persist VM-specific state.
pub const NodeContext = struct {
    const Self = @This();

    napi_env: c.napi_env,

    pub fn serialize(self: Self, value: anytype) !Serializer.NodeValue {
        return .{
            .napi_env = self.napi_env,
            .napi_value = try (Serializer{ .napi_env = self.napi_env }).serialize(value),
        };
    }

    pub fn handleError(self: Self, err: anyerror) void {
        switch (err) {
            NodeApiError.InvalidArg => {},
            NodeApiError.ObjectExpected => {},
            NodeApiError.StringExpected => {},
            NodeApiError.NameExpected => {},
            NodeApiError.FunctionExpected => {},
            NodeApiError.NumberExpected => {},
            NodeApiError.BooleanExpected => {},
            NodeApiError.ArrayExpected => {},
            NodeApiError.GenericFailure => {},
            NodeApiError.PendingException => {},
            NodeApiError.Cancelled => {},
            NodeApiError.EscapeCalledTwice => {},
            NodeApiError.HandleScopeMismatch => {},
            NodeApiError.CallbackScopeMismatch => {},
            NodeApiError.QueueFull => {},
            NodeApiError.Closing => {},
            NodeApiError.BigintExpected => {},
            NodeApiError.DateExpected => {},
            NodeApiError.ArraybufferExpected => {},
            NodeApiError.DetachableArraybufferExpected => {},
            NodeApiError.WouldDeadlock => {},
            NodeApiError.NoExternalBuffersAllowed => {},
            NodeApiError.CannotRunJs => {},
            NodeApiError.Unkown => {},
            // Only NodeApiError errors van be handled.
            else => @panic("unexpected error"),
        }

        const env = self.napi_env;

        var err_info: [*c]const c.napi_extended_error_info = null;
        if (c.napi_get_last_error_info(env, &err_info) != c.napi_ok) {
            @panic("failed to call `napi_get_last_error_info`.");
        }

        // TODO: https://nodejs.org/api/n-api.html#error-handling
    }
};
