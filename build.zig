const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Server
    const server_module = b.createModule(.{
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    const server_exe = b.addExecutable(.{
        .name = "UAV_Streaming_Server",
        .root_module = server_module,
    });
    b.installArtifact(server_exe);

    // Client
    const client_module = b.createModule(.{
        .root_source_file = b.path("src/client.zig"),
        .target = target,
        .optimize = optimize,
    });
    const client_exe = b.addExecutable(.{
        .name = "UAV_Streaming_Client",
        .root_module = client_module,
    });
    b.installArtifact(client_exe);

    // Run Commands
    const server_run_cmd = b.addRunArtifact(server_exe);
    const client_run_cmd = b.addRunArtifact(client_exe);

    server_run_cmd.step.dependOn(b.getInstallStep());
    client_run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        server_run_cmd.addArgs(args);
        client_run_cmd.addArgs(args);
    }

    const server_run_step = b.step("run_server", "Run the Server");
    const client_run_step = b.step("run_client", "Run the Client");

    server_run_step.dependOn(&server_run_cmd.step);
    client_run_step.dependOn(&client_run_cmd.step);

    // Test Commands

    const server_unit_tests = b.addTest(.{
        .root_module = server_module,
    });
    const client_unit_tests = b.addTest(.{
        .root_module = client_module,
    });

    const run_server_unit_tests = b.addRunArtifact(server_unit_tests);
    const run_client_unit_tests = b.addRunArtifact(client_unit_tests);

    const test_server_step = b.step("test_server", "Run Server unit tests");
    const test_client_step = b.step("test_client", "Run Client unit tests");

    test_server_step.dependOn(&run_server_unit_tests.step);
    test_client_step.dependOn(&run_client_unit_tests.step);
}
