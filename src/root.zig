const std = @import("std");

pub const InitFunction = fn () void;

pub fn register(comptime init: InitFunction) void {
    const mod = struct {
        pub fn napi_register_module_v1() callconv(.c) void {
            init();
        }
    };

    @export(&mod.napi_register_module_v1, .{ .name = "napi_register_module_v1" });
}
