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

    const is_root_package = b.pkg_hash.len == 0;

    if (is_root_package) {
        // zig build (test modules)
        const build_mods_step = b.step("test-modules", "build native zig modules");
        {
            var dir = std.fs.cwd().openDir("tests/zig_modules", .{ .iterate = true }) catch unreachable;
            defer dir.close();

            var it = dir.iterate();
            while (it.next() catch unreachable) |entry| {
                switch (entry.kind) {
                    .directory => {
                        std.log.info("tests/zig_modules/{s}/src/root.zig", .{entry.name});

                        const mod = b.addLibrary(.{
                            // imprtant, works without on MacOS, but not on Linux
                            .use_llvm = true,
                            .linkage = .dynamic,
                            .name = entry.name,
                            .root_module = b.createModule(.{
                                .root_source_file = b.path(std.fmt.allocPrint(b.allocator, "tests/zig_modules/{s}/src/root.zig", .{entry.name}) catch unreachable),
                                .optimize = optimize,
                                .target = target,
                            }),
                        });
                        mod.root_module.addImport("node-api", node_api);

                        // important
                        mod.linker_allow_shlib_undefined = true;
                        mod.linkLibC();

                        const sub_path = std.fmt.allocPrint(b.allocator, "{s}.node", .{entry.name}) catch |err| {
                            std.log.info("{s}", .{@errorName(err)});
                            unreachable;
                        };
                        std.log.info("sub path: {s}", .{sub_path});

                        build_mods_step.dependOn(
                            &b.addInstallArtifact(
                                mod,
                                .{
                                    // custom dir is relative to ./zig-out
                                    .dest_dir = .{ .override = .{
                                        .custom = "../tests/zig_modules",
                                    } },

                                    .dest_sub_path = sub_path,
                                },
                            ).step,
                        );
                    },
                    else => {},
                }
            }
        }

        // `zig build test`
        const test_step = b.step("test", "test bindings");
        {
            const run_cmd = b.addSystemCommand(&.{"bun"});
            run_cmd.addArg("test");
            run_cmd.cwd = .{ .cwd_relative = "tests" };
            run_cmd.step.dependOn(build_mods_step);

            test_step.dependOn(&run_cmd.step);
        }
    }
}
