const std = @import("std");
const common = @import("../common/common.zig");
const shared_memory = @import("shared.zig");
const ffmpeg = @import("ffmpeg");
const Decoder = @import("decoder.zig").Decoder;
const MP4 = @import("mp4.zig").MP4;
const Image = @import("image.zig").Image;
const Queue = @import("queue.zig").Queue;

const OptimisticDecoder = struct {
    current_packet_id: ?u64,
    start_packet_id: u64,
    shared_memory: *shared_memory.SharedMemory,
    stats_file: std.fs.File,
    stats_writer: std.fs.File.Writer,
    keyframe_queue: *Queue(u64, 255),
    img: Image,
    decoder: Decoder,

    pub fn init(id: u8, folder: std.fs.Dir, shared_mem: *shared_memory.SharedMemory) !@This() {
        var buffer: [255]u8 = undefined;
        var file = try folder.createFile(
            try std.fmt.bufPrint(&buffer, "image-latency-{}.csv", .{id}),
            .{},
        );

        return .{
            .current_packet_id = null,
            .start_packet_id = 0,
            .shared_memory = shared_mem,
            .stats_file = file,
            .stats_writer = file.writer(),
            .keyframe_queue = &shared_mem.key_frames[id],
            .img = try .init(),
            .decoder = try .init(),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.img.deinit();
        self.decoder.deinit();
        self.stats_file.close();
    }

    pub fn reinitialize(self: *@This()) !void {
        std.debug.assert(self.current_packet_id != null);
        try self.decoder.reinitialize();
    }

    pub fn free(self: *@This()) !void {
        self.current_packet_id = null;
        try self.submitPacket(null);
    }

    pub fn run(self: *@This(), stop_signal: *std.atomic.Value(bool)) !void {
        errdefer self.shared_memory.setCrashed();

        while (!stop_signal.load(.unordered)) {
            if (self.current_packet_id == null) {
                self.current_packet_id = self.keyframe_queue.pop() orelse continue;
                self.start_packet_id = self.current_packet_id.?;
                try self.reinitialize();
            }

            var packet = self.shared_memory.frame_packet_buffer.getFramePacket(
                self.current_packet_id.?,
                .Packet,
            ) orelse {
                var packet = self.shared_memory.frame_packet_buffer.getFramePacket(
                    self.current_packet_id.?,
                    .PacketWritten,
                ) orelse continue;
                if (packet.is_key_frame) {
                    packet.mutex.unlock();
                    try self.free();
                    continue;
                }
                packet.mutex.unlock();
                continue;
            };

            if (packet.is_key_frame and self.start_packet_id != self.current_packet_id) {
                packet.mutex.unlock();
                try self.free();
                continue;
            }

            try self.submitPacket(packet.frame_packet.Packet);
            packet.mutex.unlock();
            self.current_packet_id.? +%= 1;
        }
    }

    pub fn submitPacket(self: *@This(), packet: ?*ffmpeg.AVPacket) !void {
        try self.decoder.submitPacket(packet);

        while (try self.decoder.getFrame()) |frame| {
            defer self.decoder.endFrame();
            const frame_id: u64 = @bitCast(frame.*.pts);

            var pkt = self.shared_memory.frame_packet_buffer.getFramePacket(
                frame_id,
                .Packet,
            ) orelse return error.CouldNotGetFramePacket;
            defer pkt.mutex.unlock();

            pkt.frame_packet_type.store(.PacketWritten, .unordered);
            try self.writeFrame(frame, pkt.timestamp);
        }
    }

    pub fn writeFrame(self: *@This(), frame: *ffmpeg.AVFrame, generated_time: i64) !void {
        const frame_id: u64 = @bitCast(frame.*.pts);

        const current_time = std.time.milliTimestamp();
        try self.stats_writer.print(
            "{d},{d}\n",
            .{ frame_id, current_time - generated_time },
        );

        var filename: [255]u8 = undefined;
        try self.img.write(
            try std.fmt.bufPrint(
                filename[0..255],
                "Output/Frames/frame-{d}.jpg",
                .{frame_id},
            ),
            frame,
        );
    }
};

const Player = struct {
    current_packet_id: u64,
    last_timestamp: i64,
    shared_memory: *shared_memory.SharedMemory,
    stats_file: std.fs.File,
    stats_writer: std.fs.File.Writer,
    decoder: Decoder,
    mp4: MP4,

    pub fn init(folder: std.fs.Dir, shared_mem: *shared_memory.SharedMemory) !@This() {
        var file = try folder.createFile("playback-latency.csv", .{});
        return .{
            .current_packet_id = 0,
            .shared_memory = shared_mem,
            .stats_file = file,
            .stats_writer = file.writer(),
            .decoder = try .init(),
            .mp4 = try .init("Output/output.mp4"),
            .last_timestamp = 0,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.submitPacket(null) catch {};
        self.mp4.deinit();
        self.stats_file.close();
        self.decoder.deinit();
    }

    pub fn decode(self: *@This()) !void {
        var packet = self.shared_memory.frame_packet_buffer.getFramePacket(
            self.current_packet_id,
            .PacketWritten,
        ) orelse return;
        defer packet.mutex.unlock();
        defer self.current_packet_id +%= 1;

        try self.submitPacket(packet.frame_packet.Packet);
    }

    pub fn submitPacket(self: *@This(), packet: ?*ffmpeg.AVPacket) !void {
        try self.decoder.submitPacket(packet);
        while (try self.decoder.getFrame()) |frame| {
            defer self.decoder.endFrame();
            const frame_id: u64 = @bitCast(frame.*.pts);

            var pkt = self.shared_memory.frame_packet_buffer.getFramePacket(
                frame_id,
                .PacketWritten,
            ) orelse return error.CouldNotGetFramePacket;
            defer pkt.mutex.unlock();

            pkt.frame_packet_type.store(.None, .unordered);
            ffmpeg.av_packet_free(@ptrCast(&pkt.frame_packet.Packet));
            pkt.frame_packet = .{ .None = {} };

            try self.writeFrame(frame, pkt.timestamp);
        }
    }

    pub fn writeFrame(self: *@This(), frame: *ffmpeg.AVFrame, generated_time: i64) !void {
        const frame_id: u64 = @bitCast(frame.*.pts);

        const current_time = std.time.milliTimestamp();
        try self.stats_writer.print(
            "{d},{d}\n",
            .{ frame_id, current_time - generated_time },
        );
        try self.mp4.write(frame);
        self.last_timestamp = current_time;
    }
};

pub const DecoderLoop = struct {
    const NumberOfDecoders = shared_memory.SharedMemory.NumberOfDecoders;
    shared_memory: *shared_memory.SharedMemory,
    decoders: [NumberOfDecoders]OptimisticDecoder,
    player: Player,

    pub fn init(shared_mem: *shared_memory.SharedMemory) !@This() {
        // Create Output directory if it doesn't exist
        var folder = std.fs.cwd().openDir("Output", .{}) catch |err| blk: {
            if (err == std.fs.File.OpenError.FileNotFound) {
                try std.fs.cwd().makeDir("Output");
                break :blk try std.fs.cwd().openDir("Output", .{});
            }
            return err;
        };
        // Create Frames directory. If it exists error.
        try folder.makeDir("Frames");

        var decoders: [NumberOfDecoders]OptimisticDecoder = undefined;
        for (0..NumberOfDecoders) |i| {
            decoders[i] = try .init(@intCast(i), folder, shared_mem);
        }

        return .{
            .shared_memory = shared_mem,
            .decoders = decoders,
            .player = try .init(folder, shared_mem),
        };
    }

    pub fn deinit(self: *@This()) void {
        for (0..NumberOfDecoders) |i| {
            self.decoders[i].deinit();
        }
        self.player.deinit();
    }

    pub fn run(self: *@This()) !void {
        errdefer self.shared_memory.setCrashed();

        var stop_signal = std.atomic.Value(bool).init(false);
        errdefer stop_signal.store(true, .unordered);

        var threads: [NumberOfDecoders]std.Thread = undefined;
        for (0..NumberOfDecoders) |i| {
            threads[i] = try std.Thread.spawn(.{
                .allocator = self.shared_memory.allocator,
                .stack_size = 16 * 1024 * 1024,
            }, OptimisticDecoder.run, .{ &self.decoders[i], &stop_signal });
        }

        while (!self.shared_memory.hasCrashed()) {
            try self.player.decode();

            if (self.shared_memory.isStopping() and std.time.milliTimestamp() - self.player.last_timestamp > 10000) {
                break;
            }
        }

        stop_signal.store(true, .unordered);
        for (0..NumberOfDecoders) |i| {
            threads[i].join();
        }
    }
};
