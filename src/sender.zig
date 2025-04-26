const std = @import("std");
const common = @import("common.zig");
const parse = @import("parse.zig");

const SourceType = enum {
    Test,
    Camera,
};

const SenderArguments = struct {
    resolution: common.Resolution,
    frame_rate: common.FrameRate,
    source: SourceType,

    pub const default: SenderArguments = .{
        .resolution = .@"2160p",
        .frame_rate = .@"60",
        .source = SourceType.Test,
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

    std.debug.print("Resolution: {}\n", .{arguements.resolution});
    std.debug.print("Frame Rate: {}\n", .{arguements.frame_rate});
    std.debug.print("Source: {}\n", .{arguements.source});
}

test "First" {
    try std.testing.expectEqual(1, 1);
}
