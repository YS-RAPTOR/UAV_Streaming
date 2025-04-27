const std = @import("std");
const common = @import("common.zig");
const source = @import("source.zig");
const parse = @import("parse.zig");
const encoder = @import("encoder.zig");

const SenderArguments = struct {
    resolution: common.Resolution,
    frame_rate: common.FrameRate,
    source: source.SourceType,

    pub const default: SenderArguments = .{
        .resolution = .@"2160p",
        .frame_rate = .@"60",
        // TODO: Change to Camera after testing
        .source = .Test,
    };
};

const help =
    \\-h, --help                 Display this help message
    \\-r, --resolution [res]     Sets the max resolution (default: 2160p)
    \\      2160p, 1440p, 1080p, 720p, 480p, 360p
    \\-f, --frame-rate [rate]    Sets the max frame rate (default: 60)
    \\      60, 48, 30, 24
    \\-s, --source [src]         Set the source type (default: Camera)
    \\      Camera, Test
    \\
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

    var src = try source.Source.init(
        arguements.source,
        arguements.resolution,
        arguements.frame_rate,
    );
    defer src.deinit();
    errdefer src.deinit();

    var enc = try encoder.H264Codec.init(
        arguements.resolution,
        arguements.frame_rate,
    );
    defer enc.deinit();
    errdefer enc.deinit();

    var frame = try common.Frame.init();
    defer frame.deinit();
    errdefer frame.deinit();

    var packet = try common.Packet.init();
    defer packet.deinit();
    errdefer packet.deinit();

    while (true) {
        const f = try frame.start();
        defer frame.end();
        errdefer frame.end();

        if (!try src.fillFrame(f)) {
            break;
        }

        std.debug.print("Frame size: {}\n", .{f.*.format});

        std.debug.print("Encoder Info: {}x{}\n", .{ enc.context.*.width, enc.context.*.height });

        var packet_iter = try enc.getPackets(f, packet);

        while (try packet_iter.next()) |pkt| {
            std.debug.print("Packet size: {}\n", .{pkt.*.size});
        }
    }
}

test "First" {
    try std.testing.expectEqual(1, 1);
}
