const ffmpeg = @import("ffmpeg");
const common = @import("../common/common.zig");
const std = @import("std");

pub const Image = struct {
    codec: *const ffmpeg.AVCodec,
    context: *ffmpeg.AVCodecContext,
    scaler: *ffmpeg.SwsContext,
    frame: common.Frame,
    resolution: common.Resolution,

    pub fn init() !@This() {
        var self: @This() = undefined;
        const codec = ffmpeg.avcodec_find_encoder(ffmpeg.AV_CODEC_ID_BMP);
        if (codec == null) {
            return error.CodecCouldNotBeFound;
        }
        self.codec = codec;
        try self.initialize(1080, false);
        return self;
    }

    pub fn deinit(self: *@This()) void {
        ffmpeg.av_frame_free(@ptrCast(&self.frame));
        ffmpeg.avcodec_free_context(@ptrCast(&self.context));
        ffmpeg.sws_freeContext(self.scaler);
    }

    pub fn initialize(self: *@This(), height: u16, comptime is_initialized: bool) !void {
        const resolution: common.Resolution = @enumFromInt(height);
        if (self.resolution == resolution and is_initialized) {
            return;
        }
        if (is_initialized) {
            self.deinit();
        }

        self.context = blk: {
            const context = ffmpeg.avcodec_alloc_context3(self.codec);
            if (context == null) {
                return error.CouldNotAllocateContext;
            }
            break :blk context;
        };
        errdefer ffmpeg.avcodec_free_context(@ptrCast(&self.context));

        const width: u16 = resolution.getResolutionWidth();
        self.context.*.width = width;
        self.context.*.height = height;
        self.context.*.pix_fmt = ffmpeg.AV_PIX_FMT_BGR24;
        self.context.*.time_base = .{ .num = 1, .den = 1 };

        if (ffmpeg.avcodec_open2(self.context, self.codec, null) < 0) {
            return error.CouldNotOpenCodec;
        }

        self.scaler = ffmpeg.sws_getContext(
            width,
            height,
            ffmpeg.AV_PIX_FMT_NV12,
            width,
            height,
            ffmpeg.AV_PIX_FMT_BGR24,
            ffmpeg.SWS_FAST_BILINEAR,
            null,
            null,
            null,
        ) orelse return error.ScalerCouldNotBeInitialize;
        errdefer ffmpeg.sws_freeContext(self.scaler);

        self.frame = try .init();
        errdefer self.frame.deinit();

        self.frame.frame.*.width = width;
        self.frame.frame.*.height = height;
        self.frame.frame.*.format = ffmpeg.AV_PIX_FMT_BGR24;
    }

    pub fn write(self: *@This(), filename: []const u8, frame: *ffmpeg.AVFrame) !void {
        try self.initialize(@intCast(frame.*.height), true);

        const scaled_frame = try self.frame.start();
        defer self.frame.end();

        var current_time = std.time.milliTimestamp();
        if (ffmpeg.sws_scale_frame(self.scaler, scaled_frame, frame) < 0) {
            return error.CouldNotScaleFrame;
        }
        var end_time = std.time.milliTimestamp();

        var packet: *ffmpeg.AVPacket = ffmpeg.av_packet_alloc() orelse return error.PacketCouldNotBeAllocated;
        defer ffmpeg.av_packet_free(@ptrCast(&packet));

        if (ffmpeg.avcodec_send_frame(self.context, scaled_frame) < 0) {
            return error.CouldNotSendFrame;
        }

        if (ffmpeg.avcodec_receive_packet(self.context, packet) < 0) {
            return error.CouldNotReceivePacket;
        }
        current_time = std.time.milliTimestamp();

        const file = try std.fs.cwd().createFile(filename, .{ .exclusive = true });
        try file.writeAll(packet.*.data[0..@intCast(packet.*.size)]);
        file.close();
        end_time = std.time.milliTimestamp();
    }
};
