const std = @import("std");
const common = @import("./common/common.zig");
const parse = @import("./common/parse.zig");
const builtins = @import("builtin");
const SharedMemory = @import("./receiver/shared.zig").SharedMemory;
const TransferLoop = @import("./receiver/transfer_loop.zig").TransferLoop;
const DecoderLoop = @import("./receiver/decoder_loop.zig").DecoderLoop;
const ffmpeg = @import("ffmpeg");

const ReceiverArguments = struct {
    send_address: []const u8,
    bind_address: []const u8,

    pub const default: @This() = .{
        // TODO: Change when testing
        // .send_address = "127.0.0.1:2002",
        // .bind_address = "127.0.0.1:2003",
        .send_address = "127.0.0.1:2003",
        .bind_address = "127.0.0.1:2004",
    };
};

const help =
    \\-h, --help                 Display this help message
    \\-s, --send-address [addr]  Set the video address to send the video to (default: 127.0.0.1:2003)
    \\-b, --bind-address [addr]  Set the address that binds the sender to (default:127.0.0.1:2002)
;

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
const allocator = switch (builtins.mode) {
    .Debug, .ReleaseSafe => debug_allocator.allocator(),
    .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
};

const is_debug = switch (builtins.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

pub fn main() !void {
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    const arguments = parse.parse(ReceiverArguments, &args) catch |err| {
        if (err == error.HelpRequested) {
            common.print(help, .{});
            return;
        }

        common.print("Run with --help to see available options.\n", .{});
        return;
    };

    const send_address, const send_port = parse.getAddress(
        arguments.send_address,
    ) catch |err| {
        common.print("Invalid send address: {}\n", .{err});
        return;
    };
    const bind_address, const bind_port = parse.getAddress(
        arguments.bind_address,
    ) catch |err| {
        common.print("Invalid bind address: {}\n", .{err});
        return;
    };

    var shared_memory: SharedMemory = try .init(allocator);
    defer shared_memory.deinit();

    var transfer_loop = TransferLoop.init(
        allocator,
        bind_address,
        bind_port,
        send_address,
        send_port,
        &shared_memory,
    ) catch |err| {
        common.print("Failed to initialize transfer loop: {}\n", .{err});
        return;
    };
    defer transfer_loop.deinit();

    var decoder_loop = DecoderLoop.init(
        &shared_memory,
    ) catch |err| {
        common.print("Failed to initialize decoder loop: {}\n", .{err});
        return;
    };
    defer decoder_loop.deinit();

    const thread = std.Thread.spawn(
        .{
            .allocator = allocator,
            .stack_size = 16 * 1024 * 1024,
        },
        DecoderLoop.run,
        .{&decoder_loop},
    ) catch |err| {
        common.print("Error spawning thread: {}\n", .{err});
        return;
    };
    defer thread.join();

    try transfer_loop.run();
}
