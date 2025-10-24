const std = @import("std");
const lib = @import("c.zig");
const c = lib.c;

pub const Registry = struct {
    var wrapped_instances: std.AutoHashMap(usize, c.napi_value) = std.AutoHashMap(usize, c.napi_value).init(std.heap.c_allocator);

    pub fn get(native_ptr: *anyopaque) ?c.napi_value {
        return wrapped_instances.get(@intFromPtr(native_ptr));
    }

    pub fn track(native_ptr: *anyopaque, napi_value: c.napi_value) !void {
        try wrapped_instances.put(@intFromPtr(native_ptr), napi_value);
    }

    pub fn untrack(native_ptr: *anyopaque) bool {
        return try wrapped_instances.remove(@intFromPtr(native_ptr));
    }
};
