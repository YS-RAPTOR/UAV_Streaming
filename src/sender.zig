const std = @import("std");
const ffmpeg = @import("ffmpeg");
const common = @import("./common/common.zig");
const parse = @import("./common/parse.zig");
const SharedMemory = @import("./sender/shared.zig").SharedMemory;
const TransferLoop = @import("./sender/transfer_loop.zig").TransferLoop;
const encoder_loop = @import("./sender/encoder_loop.zig");

const builtins = @import("builtin");

const SenderArguments = struct {
    resolution: common.Resolution,
    frame_rate: common.FrameRate,
    type: encoder_loop.SupportedTypes,
    device: []const u8,
    send_address: []const u8,
    bind_address: []const u8,

    pub const default: SenderArguments = .{
        .resolution = .@"1080p",
        .frame_rate = .@"60",
        .type = .Test,
        .device = "/dev/video0",
        .send_address = "127.0.0.1:2003",
        .bind_address = "127.0.0.1:2002",
    };
};

const help =
    \\-h, --help                 Display this help message
    \\-r, --resolution [res]     Sets the max resolution (default: 2160p)
    \\      2160p, 1440p, 1080p, 720p, 480p, 360p
    \\-f, --frame-rate [rate]    Sets the max frame rate (default: 60)
    \\      60, 30
    \\-p, --type [src]           Set the source type (default: Test)
    \\      EncodedCamera, Test
    \\-d, --device [device]      Set the camera device name (default: /dev/video0)
    \\-s, --send-address [addr]  Set the video address to send the video to (default: 127.0.0.1:2003)
    \\-b, --bind-address [addr]  Set the address that binds the sender to (default:127.0.0.1:2004)
;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtins.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    const arguements = parse.parse(SenderArguments, &args) catch |err| {
        if (err == error.HelpRequested) {
            common.print(help, .{});
            return;
        }

        common.print("Run with --help to see available options.\n", .{});
        return;
    };

    var shared_memory = SharedMemory.init(
        allocator,
        arguements.resolution,
        arguements.frame_rate,
    ) catch |err| {
        common.print("Error initializing shared memory: {}\n", .{err});
        return;
    };
    defer shared_memory.deinit();

    var enc = try encoder_loop.EncoderLoop.init(
        arguements.type,
        &shared_memory,
        arguements.resolution,
        arguements.frame_rate,
        arguements.device,
    );
    defer enc.deinit();

    const send_address, const send_port = parse.getAddress(
        arguements.send_address,
    ) catch |err| {
        common.print("Invalid send address: {}\n", .{err});
        return;
    };
    const bind_address, const bind_port = parse.getAddress(
        arguements.bind_address,
    ) catch |err| {
        common.print("Invalid bind address: {}\n", .{err});
        return;
    };

    var transfer_loop = TransferLoop.init(
        allocator,
        bind_address,
        bind_port,
        send_address,
        send_port,
        &shared_memory,
    ) catch |err| {
        common.print("Error initializing transfer loop: {}\n", .{err});
        return;
    };
    defer transfer_loop.deinit();

    const thread = std.Thread.spawn(
        .{
            .allocator = allocator,
            .stack_size = 16 * 1024 * 1024,
        },
        TransferLoop.run,
        .{&transfer_loop},
    ) catch |err| {
        common.print("Error spawning thread: {}\n", .{err});
        return;
    };

    try enc.run();
    thread.join();
}
