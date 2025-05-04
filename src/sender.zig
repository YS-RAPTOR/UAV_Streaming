const std = @import("std");
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

    pub const default: SenderArguments = .{
        .resolution = .@"2160p",
        .frame_rate = .@"60",
        // TODO: Change to Camera after testing
        .pipeline = .Test,
        .device = "/dev/video0",
    };
};

const help =
    \\-h, --help                 Display this help message
    \\-r, --resolution [res]     Sets the max resolution (default: 2160p)
    \\      2160p, 1440p, 1080p, 720p, 480p, 360p
    \\-f, --frame-rate [rate]    Sets the max frame rate (default: 60)
    \\      60, 30
    \\-s, --pipeline [src]       Set the source type (default: Camera)
    \\      EncodedCamera, Test
    \\-d, --device [device]      Set the camera device name (default: /dev/video0)
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
            std.debug.print(help, .{});
            return;
        }

        std.debug.print("Run with --help to see available options.\n", .{});
        return;
    };

    var pl = try pipeline.Pipeline.init(
        arguements.pipeline,
        arguements.resolution,
        arguements.frame_rate,
    );

    var shared_memory: SharedMemory = try .init(
        allocator,
        arguements.resolution,
        arguements.frame_rate,
        5,
    );
    defer shared_memory.deinit();

    const start_time = std.time.milliTimestamp();
    var frames: u32 = 0;

    while (true) {
        defer frames +%= 1;

        const settings = shared_memory.getSettings();
        if (!try pl.start(settings.resolution, settings.frame_rate)) {
            break;
        }
        defer pl.end();

        if (frames > 54005) {
            break;
        }

        if (settings.frame_rate == .@"30" and frames % 2 == 1) {
            continue;
        }

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

                .is_key_frame = true,
                .generated_timestamp = @intCast(std.time.milliTimestamp() - start_time),
                .resolution = settings.resolution,
                .frame_rate = settings.frame_rate,
            });
        }
    }

    for (0..shared_memory.committed_packets.items.len) |id| {
        const packet = shared_memory.getPacket(id);
        if (packet.header.crc == 0) {
            break;
        }

        std.debug.print("{}\n", .{packet.header});
    }
}
