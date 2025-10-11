const std = @import("std");
pub const c = @cImport({
    @cInclude("node_api.h");
});

pub fn statusToError(status: c_uint) NodeApiError!void {
    const v: NapiStatusValue = @enumFromInt(status);

    if (v == NapiStatusValue.ok) {
        return;
    }

    return switch (v) {
        NapiStatusValue.invalid_arg => NodeApiError.InvalidArg,
        NapiStatusValue.object_expected => NodeApiError.ObjectExpected,
        NapiStatusValue.string_expected => NodeApiError.StringExpected,
        NapiStatusValue.name_expected => NodeApiError.NameExpected,
        NapiStatusValue.function_expected => NodeApiError.FunctionExpected,
        NapiStatusValue.number_expected => NodeApiError.NumberExpected,
        NapiStatusValue.boolean_expected => NodeApiError.BooleanExpected,
        NapiStatusValue.array_expected => NodeApiError.ArrayExpected,
        NapiStatusValue.generic_failure => NodeApiError.GenericFailure,
        NapiStatusValue.pending_exception => NodeApiError.PendingException,
        NapiStatusValue.cancelled => NodeApiError.Cancelled,
        NapiStatusValue.escape_called_twice => NodeApiError.EscapeCalledTwice,
        NapiStatusValue.handle_scope_mismatch => NodeApiError.HandleScopeMismatch,
        NapiStatusValue.callback_scope_mismatch => NodeApiError.CallbackScopeMismatch,
        NapiStatusValue.queue_full => NodeApiError.QueueFull,
        NapiStatusValue.closing => NodeApiError.Closing,
        NapiStatusValue.bigint_expected => NodeApiError.BigintExpected,
        NapiStatusValue.date_expected => NodeApiError.DateExpected,
        NapiStatusValue.arraybuffer_expected => NodeApiError.ArraybufferExpected,
        NapiStatusValue.detachable_arraybuffer_expected => NodeApiError.DetachableArraybufferExpected,
        NapiStatusValue.would_deadlock => NodeApiError.WouldDeadlock,
        NapiStatusValue.no_external_buffers_allowed => NodeApiError.NoExternalBuffersAllowed,
        NapiStatusValue.cannot_run_js => NodeApiError.CannotRunJs,
        else => NodeApiError.Unkown,
    };
}

pub const NapiStatusValue = enum(c_uint) {
    ok = 0,
    invalid_arg,
    object_expected,
    string_expected,
    name_expected,
    function_expected,
    number_expected,
    boolean_expected,
    array_expected,
    generic_failure,
    pending_exception,
    cancelled,
    escape_called_twice,
    handle_scope_mismatch,
    callback_scope_mismatch,
    queue_full,
    closing,
    bigint_expected,
    date_expected,
    arraybuffer_expected,
    detachable_arraybuffer_expected,
    would_deadlock, // /* unused */
    no_external_buffers_allowed,
    cannot_run_js,
    // non-exhaustive, just in case (translates to NodeApiError.Unkown)
    _,
};

pub const NodeApiError = error{
    InvalidArg,
    ObjectExpected,
    StringExpected,
    NameExpected,
    FunctionExpected,
    NumberExpected,
    BooleanExpected,
    ArrayExpected,
    GenericFailure,
    PendingException,
    Cancelled,
    EscapeCalledTwice,
    HandleScopeMismatch,
    CallbackScopeMismatch,
    QueueFull,
    Closing,
    BigintExpected,
    DateExpected,
    ArraybufferExpected,
    DetachableArraybufferExpected,
    WouldDeadlock,
    NoExternalBuffersAllowed,
    CannotRunJs,
    Unkown,
};

// https://nodejs.org/api/n-api.html#error-handling
pub fn handleError(env: c.napi_env, err: anyerror) void {
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
        if (info.*.error_message) |m| {
            _ = c.napi_throw_error(env, @errorName(err), std.mem.span(m));
        }
    } else {
        _ = c.napi_throw_error(env, @errorName(err), @errorName(err));
    }
}
