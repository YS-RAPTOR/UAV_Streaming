const std = @import("std");

const Dependency = struct {
    name: []const u8,
    module: *std.Build.Module,
    system_libs: []const []const u8,
};

fn create(
    b: *std.Build,
    comptime name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dependencies: []const Dependency,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path("src/" ++ name ++ ".zig"),
        .target = target,
        .optimize = optimize,
    });

    for (dependencies) |dep| {
        module.addImport(dep.name, dep.module);
        for (dep.system_libs) |lib| {
            module.linkSystemLibrary(lib, .{});
        }
    }

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = module,
    });
    exe.linkLibC();
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run_" ++ name, "Run the " ++ name);
    run_step.dependOn(&run_cmd.step);

    const unit_test = b.addTest(.{
        .root_module = module,
    });

    const run_unit_test = b.addRunArtifact(unit_test);
    const test_step = b.step("test_" ++ name, "Run the " ++ name ++ " unit tests");
    test_step.dependOn(&run_unit_test.step);

    return exe;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ffmpeg = b.addTranslateC(.{
        .root_source_file = b.path("src/c/ffmpeg.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }).createModule();

    const sdl = b.addTranslateC(.{
        .root_source_file = b.path("src/c/sdl.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }).createModule();

    const ffmpeg_dep = Dependency{
        .name = "ffmpeg",
        .module = ffmpeg,
        .system_libs = &[_][]const u8{ "avutil", "avformat", "avcodec", "avfilter", "avdevice", "libswscale" },
    };

    const receiver = create(
        b,
        "receiver",
        target,
        optimize,
        &[_]Dependency{
            ffmpeg_dep,
            .{
                .name = "sdl",
                .module = sdl,
                .system_libs = &[_][]const u8{"SDL3"},
            },
        },
    );

    const sender = create(
        b,
        "sender",
        target,
        optimize,
        &[_]Dependency{
            ffmpeg_dep,
        },
    );

    const check = b.step("check", "Check if they compile");
    check.dependOn(&receiver.step);
    check.dependOn(&sender.step);
}
