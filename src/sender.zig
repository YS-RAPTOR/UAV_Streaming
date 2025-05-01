const std = @import("std");
const common = @import("./common/common.zig");
const parse = @import("./common/parse.zig");
const pipeline = @import("./sender/pipeline.zig");

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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
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

    var count: u16 = 0;

    while (true) {
        if (!try pl.start()) {
            break;
        }
        defer pl.end();

        while (try pl.getPacket()) |packet| {
            std.debug.print("Packet: {d}\n", .{packet.size});
        }

        count += 1;

        if (count > 1000) {
            break;
        }
    }
}

test "First" {
    try std.testing.expectEqual(1, 1);
}
