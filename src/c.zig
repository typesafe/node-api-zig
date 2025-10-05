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
