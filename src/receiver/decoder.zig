const ffmpeg = @import("ffmpeg");
const std = @import("std");
const common = @import("../common/common.zig");

pub const Decoder = struct {
    codec: *const ffmpeg.AVCodec,
    context: *ffmpeg.AVCodecContext,
    frame: common.Frame,

    fn findBestCodec() !*const ffmpeg.AVCodec {
        var codec = ffmpeg.avcodec_find_decoder_by_name("h264_cuvid");

        if (codec != null) {
            return codec;
        }

        codec = ffmpeg.avcodec_find_decoder_by_name("h264_amf");
        if (codec != null) {
            return codec;
        }

        codec = ffmpeg.avcodec_find_decoder_by_name("h264_qsv");
        if (codec != null) {
            return codec;
        }

        codec = ffmpeg.avcodec_find_decoder_by_name("h264_v4l2m2m");
        if (codec != null) {
            return codec;
        }

        codec = ffmpeg.avcodec_find_decoder(ffmpeg.AV_CODEC_ID_H264);

        if (codec == null) {
            return error.CodecNotFound;
        }
        return codec;
    }

    pub fn init() !@This() {
        var self: @This() = undefined;
        self.codec = try findBestCodec();
        self.frame = try .init();
        try self.initialize();
        return self;
    }

    pub fn deinit(self: *@This()) void {
        ffmpeg.avcodec_free_context(@ptrCast(&self.context));
        self.frame.deinit();
    }

    pub fn initialize(self: *@This()) !void {
        self.context = blk: {
            const context = ffmpeg.avcodec_alloc_context3(self.codec);
            if (context == null) {
                return error.CouldNotAllocateCodecContext;
            }
            break :blk context;
        };

        self.context.pkt_timebase = .{ .num = 1, .den = 60 };

        errdefer ffmpeg.avcodec_free_context(@ptrCast(&self.context));
        if (ffmpeg.avcodec_open2(self.context, self.codec, null) < 0) {
            return error.CouldNotOpenCodec;
        }
    }

    pub fn reinitialize(self: *@This()) !void {
        ffmpeg.avcodec_free_context(@ptrCast(&self.context));
        try self.initialize();
    }

    pub fn submitPacket(self: *@This(), packet: ?*ffmpeg.AVPacket) !void {
        if (ffmpeg.avcodec_send_packet(self.context, packet) < 0) {
            return error.CouldNotSendPacket;
        }
    }

    pub fn getFrame(self: *@This()) !?*ffmpeg.AVFrame {
        const frame = try self.frame.start();

        const ret = ffmpeg.avcodec_receive_frame(self.context, frame);
        if (ret == ffmpeg.AVERROR(ffmpeg.EAGAIN) or ret == ffmpeg.AVERROR_EOF) {
            self.frame.end();
            return null;
        } else if (ret < 0) {
            return error.CouldNotReceivePacket;
        }
        return frame;
    }

    pub fn endFrame(self: *@This()) void {
        self.frame.end();
    }
};
