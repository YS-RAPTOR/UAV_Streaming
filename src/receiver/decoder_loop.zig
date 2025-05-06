const std = @import("std");
const common = @import("../common/common.zig");
const SharedMemory = @import("shared.zig").SharedMemory;
const sdl = @import("sdl");
const ffmpeg = @import("ffmpeg");
const mp4 = @import("mp4.zig");

const Decoder = struct {
    current_frame_id: ?u64, //null means it is free.
    shared_memory: *SharedMemory,
    stats_file: *std.fs.File,

    pub fn init(shared_memory: *SharedMemory, stats_file: *std.fs.File) !@This() {
        return .{
            .shared_memory = shared_memory,
            .current_frame_id = null,
            .stats_file = stats_file,
        };
    }

    pub fn free(self: *@This()) !void {
        self.current_frame_id == null;
        // Reinitialize the decoder.
    }

    pub fn deinit(self: *@This()) void {
        // TODO: Add decoder deinit
        _ = self;
    }

    pub fn decode(self: *@This()) !void {
        if (self.current_frame_id == null) {
            if (!self.shared_memory.key_frames_mutex.tryLock()) {
                return;
            }
            defer self.shared_memory.key_frames_mutex.unlock();
            self.current_frame_id = self.shared_memory.key_frames.pop() orelse {
                // No more frames to decode.
                return;
            };
        }

        // Decode the image and write it to the shared memory.
        var packet = self.shared_memory.frame_packet_buffer.getFramePacket() orelse return;
        defer packet.mutex.unlock();

        // Write the image to a file.
        // Write the latency information to a file.
    }
};

const Player = struct {
    shared_memory: *SharedMemory,
    current_frame_id: u64,
    playback_speed: common.PlayBackSpeed,
    last_frame_time: i64,
    stats_file: *std.fs.File,
    scaler: *ffmpeg.SwsContext,
    frame: *ffmpeg.AVFrame,
    mp4: *mp4.MP4,

    pub fn init(shared_memory: *SharedMemory, stats_file: *std.fs.File) !@This() {
        const scaler = ffmpeg.sws_getContext(
            common.Resolution.@"2160p".getResolutionWidth(),
            @intFromEnum(common.Resolution.@"2160p"),
            ffmpeg.AVPixelFormat.AV_PIX_FMT_YUV420P,

            common.Resolution.@"1080p".getResolutionWidth(),
            @intFromEnum(common.Resolution.@"1080p"),
            ffmpeg.AVPixelFormat.AV_PIX_FMT_RGBA,
            ffmpeg.SWS_FAST_BILINEAR,
            null,
            null,
            null,
        ) orelse return error.ScalerCouldNotBeInitialize;
        errdefer ffmpeg.sws_freeContext(scaler);

        const frame = ffmpeg.av_frame_alloc();
        if (frame == null) {
            return error.FrameCouldNotBeAllocated;
        }
        errdefer ffmpeg.av_frame_free(&frame);

        frame.*.width = common.Resolution.@"1080p".getResolutionWidth();
        frame.*.height = common.Resolution.@"1080p".getResolutionHeight();
        frame.*.format = ffmpeg.AVPixelFormat.AV_PIX_FMT_RGBA;
        const ret = ffmpeg.av_frame_get_buffer(frame, 32);
        if (ret < 0) {
            return error.FrameCouldNotBeAllocated;
        }

        return .{
            .shared_memory = shared_memory,
            .current_frame_id = 0,
            .playback_speed = .normal,
            .last_frame_time = std.time.milliTimestamp(),
            .stats_file = stats_file,
            .scaler = scaler,
            .frame = frame,
            .mp4 = try .init("Output/output.mp4"),
        };
    }

    pub fn deinit(self: *@This()) void {
        ffmpeg.av_frame_free(&self.frame);
        ffmpeg.sws_freeContext(self.scaler);
    }

    pub fn render(self: *@This()) !void {
        // Change the playback speed.
        // Get the quit event
        // Use sdl events

        const frame = self.shared_memory.frame_packet_buffer.getFramePacket(self.current_frame_id) orelse return;
        defer frame.mutex.unlock();
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
            ffmpeg.AVPixelFormat.AV_PIX_FMT_YUV420P,

            common.Resolution.@"1080p".getResolutionWidth(),
            @intFromEnum(common.Resolution.@"1080p"),
            ffmpeg.AVPixelFormat.AV_PIX_FMT_RGBA,
            ffmpeg.SWS_FAST_BILINEAR,
            null,
            null,
            null,
        );

        // Scale the frame to the screen size.
        ffmpeg.av_frame_unref(self.frame);
        ffmpeg.sws_scale(
            self.scaler,
            frame.packetFrame.Frame.*.data,
            frame.packetFrame.Frame.*.linesize,
            0,
            @intFromEnum(frame.resolution),
            self.frame.*.data,
            self.frame.*.linesize,
        );
        // TODO: Render the frame.

        try self.mp4.write(self.frame);
        //NOTE: For the mp4 if the frame rate is 30 fps double write the same frame
        if (frame.frame_rate == .@"30") {
            try self.mp4.write(self.frame);
        }

        // Write the latency information to a file.
        const writer = self.stats_file.writer();
        writer.print("{d},{d}\n", .{ self.current_frame_id, current_time - frame.timestamp });
    }
};

pub const DecoderLoop = struct {
    const NumberOfDecoders = 8;
    decoders: [NumberOfDecoders]Decoder,
    shared_memory: *SharedMemory,
    player: Player,
    image_latency_file: std.fs.File,
    playback_latency_file: std.fs.File,

    pub fn init(shared_memory: *SharedMemory) !@This() {
        try std.fs.cwd().makeDir("./Output");
        const image_latency_file = try std.fs.cwd().createFile("./Output/image-latency.csv", .{});
        const playback_latency_file = try std.fs.cwd().createFile("./Output/playback-latency.csv", .{});

        const decoders: [NumberOfDecoders]Decoder = undefined;
        for (decoders) |*decoder| {
            decoder = try Decoder.init(shared_memory, &image_latency_file);
        }

        const player = try Player.init(
            shared_memory,
            &playback_latency_file,
        );

        return .{
            .decoders = decoders,
            .player = player,
            .image_latency_file = image_latency_file,
            .playback_latency_file = playback_latency_file,
            .shared_memory = shared_memory,
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.decoders) |*decoder| {
            decoder.deinit();
        }
        self.player.deinit();
        self.image_latency_file.close();
        self.playback_latency_file.close();
    }

    pub fn run(self: *@This()) !void {
        while (true) {
            for (self.decoders) |decoder| {
                try decoder.decode();
            }
            self.player.render();

            if (self.shared_memory.isStopping() and
                self.shared_memory.no_of_frames_received.load(.unordered) +% 1 == self.player.current_frame_id)
            {
                break;
            }
        }
    }
};
