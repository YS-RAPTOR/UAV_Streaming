const std = @import("std");

fn create(b: *std.Build, comptime name: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path("src/" ++ name ++ ".zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = module,
    });
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

    const client = create(b, "receiver", target, optimize);
    const server = create(b, "sender", target, optimize);

    const check = b.step("check", "Check if they compile");
    check.dependOn(&client.step);
    check.dependOn(&server.step);
}
