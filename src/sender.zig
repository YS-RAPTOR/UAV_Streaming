const std = @import("std");
const ffmpeg = @import("ffmpeg");
const common = @import("./common/common.zig");
const parse = @import("./common/parse.zig");
const pipeline = @import("./sender/pipeline.zig");
const SharedMemory = @import("./sender/shared.zig").SharedMemory;
const TransferLoop = @import("./sender/transfer_loop.zig").TransferLoop;

const builtins = @import("builtin");

const SenderArguments = struct {
    resolution: common.Resolution,
    frame_rate: common.FrameRate,
    pipeline: pipeline.SupportedPipelines,
    device: []const u8,
    send_address: []const u8,
    bind_address: []const u8,

    pub const default: SenderArguments = .{
        .resolution = .@"1080p",
        .frame_rate = .@"60",
        // TEST: Change to Camera after testing
        .pipeline = .Test,
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
    \\-p, --pipeline [src]       Set the source type (default: Camera)
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

    var pl = pipeline.Pipeline.init(
        arguements.pipeline,
        arguements.resolution,
        arguements.frame_rate,
    ) catch |err| {
        common.print("Error initializing pipeline: {}\n", .{err});
        return;
    };
    defer pl.deinit();

    var shared_memory = SharedMemory.init(
        allocator,
        arguements.resolution,
        arguements.frame_rate,
    ) catch |err| {
        common.print("Error initializing shared memory: {}\n", .{err});
        return;
    };
    defer shared_memory.deinit();

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

    var count: u32 = 0;
    var frame_no: u64 = 0;

    while (!shared_memory.isRunning()) {}

    common.print("Starting Video Encode...\n", .{});
    while (true) {
        defer std.Thread.sleep(8000000);

        if (!shared_memory.isRunning()) {
            break;
        }

        errdefer shared_memory.crash();
        defer count +%= 1;

        const resolution, const frame_rate = blk: {
            const s = shared_memory.getSettings();
            try pl.changeSettings(s.resolution, s.frame_rate);
            break :blk pl.getSettings();
        };

        const should_skip = frame_rate == .@"30" and count % 2 == 0;
        if (!try pl.start(!should_skip)) {
            break;
        }
        defer pl.end();

        // if (count > 100) {
        //     shared_memory.crash();
        //     break;
        // }

        if (should_skip) {
            continue;
        }

        var no_of_packets: u8 = 0;
        while (try pl.getPacket()) |packet| {
            var data: []u8 = undefined;
            data.len = @intCast(packet.size);
            data.ptr = packet.data;

            shared_memory.insertPackets(data, .{
                .id = 0,
                .no_of_splits = 0,
                .parent_offset = 0,
                .size = 0,
                .crc = 0,

                .is_key_frame = (packet.flags & ffmpeg.AV_PKT_FLAG_KEY) != 0,
                .generated_timestamp = std.time.milliTimestamp(),
                .resolution = resolution,
                .frame_rate = frame_rate,
                .frame_number = frame_no,
            });

            no_of_packets += 1;
            frame_no += 1;
        }

        std.debug.assert(no_of_packets <= 1);
    }
    thread.join();
}
