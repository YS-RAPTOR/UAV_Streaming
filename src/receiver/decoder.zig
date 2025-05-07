const ffmpeg = @import("ffmpeg");
const std = @import("std");
const common = @import("../common/common.zig");

pub const Decoder = struct {
    codec: *const ffmpeg.AVCodec,
    context: *ffmpeg.AVCodecContext,

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
        try self.initialize(.@"1080p");
        return self;
    }

    pub fn deinit(self: *@This()) void {
        ffmpeg.avcodec_free_context(@ptrCast(&self.context));
    }

    pub fn initialize(self: *@This(), resolution: common.Resolution) !void {
        self.context = blk: {
            const context = ffmpeg.avcodec_alloc_context3(self.codec);
            if (context == null) {
                return error.CouldNotAllocateCodecContext;
            }
            break :blk context;
        };
        errdefer ffmpeg.avcodec_free_context(@ptrCast(&self.context));
        self.context.width = resolution.getResolutionWidth();
        self.context.height = @intFromEnum(resolution);
        self.context.time_base = .{ .num = 1, .den = 60 };
        self.context.framerate = .{ .num = 60, .den = 1 };
        self.context.pix_fmt = ffmpeg.AV_PIX_FMT_YUV420P;
        self.context.pkt_timebase = self.context.time_base;

        if (ffmpeg.avcodec_open2(self.context, self.codec, null) < 0) {
            return error.CouldNotOpenCodec;
        }
    }

    pub fn getFrame(self: *@This(), packet: *ffmpeg.AVPacket) !*ffmpeg.AVFrame {
        if (ffmpeg.avcodec_send_packet(self.context, packet) < 0) {
            return error.CouldNotSendPacket;
        }

        var frame = blk: {
            const frame = ffmpeg.av_frame_alloc();
            if (frame == null) {
                return error.CouldNotAllocateFrame;
            }
            break :blk frame;
        };
        errdefer ffmpeg.av_frame_free(@ptrCast(&frame));

        var ret: c_int = 1;
        var no_of_frames: u8 = 0;
        while (ret >= 0) {
            ret = ffmpeg.avcodec_receive_frame(self.context, frame);
            if (ret == ffmpeg.AVERROR(ffmpeg.EAGAIN) or ret == ffmpeg.AVERROR_EOF) {
                break;
            } else if (ret < 0) {
                return error.CouldNotReceiveFrame;
            }
            no_of_frames += 1;
        }

        std.debug.assert(no_of_frames == 1);
        return frame;
    }
};
