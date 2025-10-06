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

    pub fn deserializeValue(self: Self, comptime T: type, value: Serializer.NodeValue) !T {
        return (Serializer{ .napi_env = self.napi_env }).deserializeValue(T, value.napi_value);
    }

    pub fn handleError(self: Self, err: anyerror) void {
        // https://nodejs.org/api/n-api.html#error-handling

        const env = self.napi_env;

        var err_info: [*c]const c.napi_extended_error_info = undefined;
        if (c.napi_get_last_error_info(env, &err_info) != c.napi_ok) {
            @panic("failed to call `napi_get_last_error_info`.");
        }
        std.log.debug("err_infooo {s}", .{err_info.*.error_message});

        // In many cases when a Node-API function is called and an exception is already pending, the function will return immediately with a napi_status of napi_pending_exception.
        // However, this is not the case for all functions. Node-API allows a subset of the functions to be called to allow for some minimal cleanup before returning to JavaScript.
        // In that case, napi_status will reflect the status for the function. It will not reflect previous pending exceptions. To avoid confusion, check the error status after every function call.
        var pending_exception: bool = undefined;
        if (err != NodeApiError.PendingException) {
            if (c.napi_is_exception_pending(env, &pending_exception) != c.napi_ok) {
                @panic("failed to call `napi_get_last_error_info`.");
            }
        } else {
            pending_exception = true;
        }

        std.log.debug("pending_expeption {any}", .{pending_exception});

        if (pending_exception) {
            // the pending exception will be thrown in JS
            return;
        }

        // TODO: https://nodejs.org/api/n-api.html#error-handling

        if (err_info) |info| {
            if (info.?.error_message) |m| {
                _ = c.napi_throw_error(env, @errorName(err), std.mem.span(m));
            }
        } else {
            _ = c.napi_throw_error(env, @errorName(err), @errorName(err));
        }
    }
};
