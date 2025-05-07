const std = @import("std");
const common = @import("../common/common.zig");
const shared_memory = @import("shared.zig");
const sdl = @import("sdl");
const ffmpeg = @import("ffmpeg");
const mp4 = @import("mp4.zig");
const png = @import("png.zig");
const decoder = @import("decoder.zig");

const OptimisticDecoder = struct {
    current_frame_id: ?u64, //null means it is free.
    shared_memory: *shared_memory.SharedMemory,
    stats_file: *std.fs.File,
    png: png.PNG,
    decoder: decoder.Decoder,

    pub fn init(shared_mem: *shared_memory.SharedMemory, stats_file: *std.fs.File) !@This() {
        return .{
            .shared_memory = shared_mem,
            .current_frame_id = null,
            .stats_file = stats_file,
            .png = try .init(),
            .decoder = try .init(),
        };
    }

    pub fn free(self: *@This()) void {
        self.current_frame_id = null;
    }

    pub fn reinitialize(self: *@This(), resolution: common.Resolution) !void {
        std.debug.assert(self.current_frame_id != null);
        self.decoder.deinit();
        try self.decoder.initialize(resolution);
    }

    pub fn deinit(self: *@This()) void {
        self.png.deinit();
        self.decoder.deinit();
    }

    pub fn decode(self: *@This()) !void {
        var should_reinitialize = false;
        if (self.current_frame_id == null) {
            if (!self.shared_memory.key_frames_mutex.tryLock()) {
                return;
            }
            defer self.shared_memory.key_frames_mutex.unlock();
            self.current_frame_id = self.shared_memory.key_frames.pop() orelse {
                return;
            };
            should_reinitialize = true;
        }

        var packet = self.shared_memory.frame_packet_buffer.getFramePacket(self.current_frame_id.?) orelse return;
        defer packet.mutex.unlock();

        if (packet.packetFrame != .Packet or packet.is_key_frame) {
            self.free();
            return;
        }

        if (should_reinitialize) {
            try self.reinitialize(packet.resolution);
        }

        var packet_data = packet.packetFrame.Packet;
        defer ffmpeg.av_packet_free(@ptrCast(&packet_data));

        // Decode the image and write it to the shared memory.
        var frame = try self.decoder.getFrame(packet_data);
        errdefer ffmpeg.av_frame_free(@ptrCast(&frame));
        packet.packetFrame = .{ .Frame = frame };

        // Write the image to a file.
        var filename: [255]u8 = undefined;
        try self.png.write(
            try std.fmt.bufPrint(filename[0..255], "Output/frame-{d}.png", .{self.current_frame_id.?}),
            packet.resolution,
            packet.packetFrame.Frame,
        );

        // Write the latency information to a file.
        const writer = self.stats_file.writer();
        const current_time = std.time.milliTimestamp();
        try writer.print("{d},{d}\n", .{ self.current_frame_id.?, current_time - packet.timestamp });
    }
};

const Player = struct {
    shared_memory: *shared_memory.SharedMemory,
    current_frame_id: u64,
    playback_speed: common.PlayBackSpeed,
    last_frame_time: i64,
    stats_file: *std.fs.File,
    scaler: *ffmpeg.SwsContext,
    frame: *ffmpeg.AVFrame,
    mp4: mp4.MP4,

    pub fn init(shared_mem: *shared_memory.SharedMemory, stats_file: *std.fs.File) !@This() {
        const scaler = ffmpeg.sws_getContext(
            common.Resolution.@"1080p".getResolutionWidth(),
            @intFromEnum(common.Resolution.@"1080p"),
            ffmpeg.AV_PIX_FMT_YUV420P,

            common.Resolution.@"1080p".getResolutionWidth(),
            @intFromEnum(common.Resolution.@"1080p"),
            ffmpeg.AV_PIX_FMT_RGBA,
            ffmpeg.SWS_FAST_BILINEAR,
            null,
            null,
            null,
        ) orelse return error.ScalerCouldNotBeInitialize;
        errdefer ffmpeg.sws_freeContext(scaler);

        var frame = ffmpeg.av_frame_alloc();
        if (frame == null) {
            return error.FrameCouldNotBeAllocated;
        }
        errdefer ffmpeg.av_frame_free(@ptrCast(&frame));

        frame.*.width = common.Resolution.@"1080p".getResolutionWidth();
        frame.*.height = @intFromEnum(common.Resolution.@"1080p");
        frame.*.format = ffmpeg.AV_PIX_FMT_RGBA;
        const ret = ffmpeg.av_frame_get_buffer(frame, 32);
        if (ret < 0) {
            return error.FrameCouldNotBeAllocated;
        }

        return .{
            .shared_memory = shared_mem,
            .current_frame_id = 0,
            .playback_speed = .normal,
            .last_frame_time = std.time.milliTimestamp(),
            .stats_file = stats_file,
            .scaler = scaler,
            .frame = frame,
            .mp4 = try .init("Output/output.mp4", .@"1080p", .@"60"),
        };
    }

    pub fn deinit(self: *@This()) void {
        ffmpeg.av_frame_free(@ptrCast(&self.frame));
        ffmpeg.sws_freeContext(self.scaler);
    }

    pub fn render(self: *@This()) !void {
        // Change the playback speed.
        // Get the quit event
        // Use sdl events

        var frame = self.shared_memory.frame_packet_buffer.getFramePacket(self.current_frame_id) orelse return;
        defer frame.mutex.unlock();

        if (frame.packetFrame != .Frame) {
            return;
        }

        const frame_time = frame.frame_rate.getFrameTime(self.playback_speed);

        const current_time = std.time.milliTimestamp();
        if (current_time - self.last_frame_time < frame_time) {
            return;
        }
        defer self.current_frame_id += 1;
        defer self.last_frame_time = current_time;

        self.scaler = ffmpeg.sws_getCachedContext(
            self.scaler,
            frame.resolution.getResolutionWidth(),
            @intFromEnum(frame.resolution),
            ffmpeg.AV_PIX_FMT_YUV420P,

            common.Resolution.@"1080p".getResolutionWidth(),
            @intFromEnum(common.Resolution.@"1080p"),
            ffmpeg.AV_PIX_FMT_RGBA,
            ffmpeg.SWS_FAST_BILINEAR,
            null,
            null,
            null,
        ) orelse return error.ScalerCouldNotBeInitialize;

        // Scale the frame to the screen size.
        ffmpeg.av_frame_unref(self.frame);
        if (ffmpeg.sws_scale(
            self.scaler,
            &frame.packetFrame.Frame.*.data,
            &frame.packetFrame.Frame.*.linesize,
            0,
            @intFromEnum(frame.resolution),
            &self.frame.*.data,
            &self.frame.*.linesize,
        ) < 0) {
            return error.CouldNotScaleFrame;
        }

        // TODO: Render the frame.

        try self.mp4.write(self.frame);
        //NOTE: For the mp4 if the frame rate is 30 fps double write the same frame
        if (frame.frame_rate == .@"30") {
            try self.mp4.write(self.frame);
        }

        // Write the latency information to a file.
        const writer = self.stats_file.writer();
        try writer.print("{d},{d}\n", .{ self.current_frame_id, current_time - frame.timestamp });
    }
};

pub const DecoderLoop = struct {
    const NumberOfDecoders = 8;
    decoders: [NumberOfDecoders]OptimisticDecoder,
    shared_memory: *shared_memory.SharedMemory,
    player: Player,
    image_latency_file: std.fs.File,
    playback_latency_file: std.fs.File,

    pub fn init(shared_mem: *shared_memory.SharedMemory) !@This() {
        var folder = std.fs.cwd().openDir("Output", .{}) catch |err| blk: {
            if (err == std.fs.File.OpenError.FileNotFound) {
                try std.fs.cwd().makeDir("Output");
                break :blk try std.fs.cwd().openDir("Output", .{});
            }
            return err;
        };

        var image_latency_file = try folder.createFile("image-latency.csv", .{});
        var playback_latency_file = try folder.createFile("playback-latency.csv", .{});

        var decoders: [NumberOfDecoders]OptimisticDecoder = undefined;

        for (0..NumberOfDecoders) |i| {
            decoders[i] = try OptimisticDecoder.init(shared_mem, &image_latency_file);
        }

        const player = try Player.init(
            shared_mem,
            &playback_latency_file,
        );

        return .{
            .decoders = decoders,
            .player = player,
            .image_latency_file = image_latency_file,
            .playback_latency_file = playback_latency_file,
            .shared_memory = shared_mem,
        };
    }

    pub fn deinit(self: *@This()) void {
        for (0..NumberOfDecoders) |i| {
            self.decoders[i].deinit();
        }

        self.player.deinit();
        self.image_latency_file.close();
        self.playback_latency_file.close();
    }

    pub fn run(self: *@This()) !void {
        while (true) {
            for (0..NumberOfDecoders) |i| {
                try self.decoders[i].decode();
            }
            try self.player.render();

            if (self.shared_memory.isStopping() and
                self.shared_memory.no_of_frames_received.load(.unordered) +% 1 == self.player.current_frame_id)
            {
                break;
            }
        }
    }
};
