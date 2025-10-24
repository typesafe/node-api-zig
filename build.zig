const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const node_api = b.addModule("node-api", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const node_api_headers = b.dependency("node_api_headers", .{
        .optimize = optimize,
        .target = target,
    });

    node_api.addSystemIncludePath(node_api_headers.path("include"));

    const sample_addon = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "sample-addon",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/zig/test-module.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });
    sample_addon.root_module.addImport("node-api", node_api);

    // important
    sample_addon.linker_allow_shlib_undefined = true;
    sample_addon.linkLibC();

    const install_step = b.getInstallStep();

    install_step.dependOn(
        &b.addInstallArtifact(
            sample_addon,
            .{
                // custom dir is relative to ./zig-out
                .dest_dir = .{ .override = .{ .custom = "../tests/node_modules/node-api-test-module" } },
                .dest_sub_path = "zig-module.node",
            },
        ).step,
    );

    // `zig build test`
    {
        const run_cmd = b.addSystemCommand(&.{"bun"});
        run_cmd.addArg("test");
        run_cmd.cwd = .{ .cwd_relative = "tests" };
        run_cmd.step.dependOn(install_step);

        const test_step = b.step("test", "test bindings");
        test_step.dependOn(&run_cmd.step);
    }
}
