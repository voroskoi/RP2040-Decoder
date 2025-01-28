const std = @import("std");

pub fn build(b: *std.Build) !void {
    // Options
    const BoardVersion = enum {
        @"1.0",
        @"0.3",
    };
    const board_version = b.option(BoardVersion, "board_version", "Board version") orelse .@"1.0";
    const loglevel = b.option(u2, "loglevel", "Logging level") orelse 0;

    const target = std.Target.Query{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
        .os_tag = .freestanding,
        .abi = .eabi,
    };
    const optimize = b.standardOptimizeOption(.{});

    const firmware = b.addExecutable(std.Build.ExecutableOptions{
        .name = "decoder",
        .target = b.resolveTargetQuery(target),
        .optimize = optimize,
    });

    const pico_sdk = b.dependency("pico-sdk", .{});
    firmware.root_module.linkLibrary(pico_sdk.artifact("pico-sdk"));

    firmware.addCSourceFiles(.{ .files = &.{ "core0.c", "core1.c", "shared.c" } });

    const newlib = pico_sdk.module("newlib").root_source_file.?.dependency.dependency;
    firmware.addIncludePath(newlib.path("newlib/libc/include"));

    const pico_sdk_build = @import("pico-sdk");
    for (try pico_sdk_build.includeDirs(pico_sdk.builder, .{ .platform = .rp2040 })) |include| {
        firmware.addIncludePath(pico_sdk.path(include));
    }

    const version_h = b.addConfigHeader(.{
        .style = .{ .cmake = pico_sdk.path("src/common/pico_base_headers/include/pico/version.h.in") },
        .include_path = "pico/version.h",
    }, .{
        .PICO_SDK_VERSION_MAJOR = 2,
        .PICO_SDK_VERSION_MINOR = 1,
        .PICO_SDK_VERSION_REVISION = 0,
        .PICO_SDK_VERSION_STRING = "2.1.0",
    });
    firmware.addConfigHeader(version_h);

    switch (board_version) {
        .@"1.0" => {
            var buf: [1024]u8 = undefined;
            const board_include = b.addWriteFile(
                "pico/config_autogen.h",
                try std.fmt.bufPrint(
                    &buf,
                    "#include \"{s}\"",
                    .{b.path("RP2040-Decoder-board-Rev-1_0.h").getPath(b)},
                ),
            );
            firmware.addIncludePath(board_include.getDirectory());
            firmware.step.dependOn(&board_include.step);
        },
        .@"0.3" => {
            unreachable;
        },
    }

    {
        var buf: [1024]u8 = undefined;
        firmware.root_module.addCMacro("PICO_RP2040", "1");
        firmware.root_module.addCMacro("LOGLEVEL", try std.fmt.bufPrint(&buf, "{d}", .{loglevel}));
    }

    b.installArtifact(firmware);
}
