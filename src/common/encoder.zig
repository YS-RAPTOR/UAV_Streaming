const ffmpeg = @import("ffmpeg");
const common = @import("../common/common.zig");
const std = @import("std");

pub const H264Codec = struct {
    codec: *const ffmpeg.AVCodec,
    context: *ffmpeg.AVCodecContext,

    fn findBestCodec() !*const ffmpeg.AVCodec {
        var codec = ffmpeg.avcodec_find_encoder_by_name("h264_nvenc");

        if (codec != null) {
            common.print("Using NVENC codec\n", .{});
            return codec;
        }

        codec = ffmpeg.avcodec_find_encoder_by_name("h264_amf");
        if (codec != null) {
            common.print("Using AMF codec\n", .{});
            return codec;
        }

        codec = ffmpeg.avcodec_find_encoder_by_name("h264_qsv");
        if (codec != null) {
            common.print("Using QSV codec\n", .{});
            return codec;
        }

        codec = ffmpeg.avcodec_find_encoder_by_name("h264_v4l2m2m");
        if (codec != null) {
            common.print("Using V4L2M2M codec\n", .{});
            return codec;
        }

        codec = ffmpeg.avcodec_find_encoder(ffmpeg.AV_CODEC_ID_H264);

        if (codec == null) {
            return error.CodecNotFound;
        }
        common.print("Using default H264 codec\n", .{});
        return codec;
    }

    pub fn init(resolution: common.Resolution, frame_rate: common.FrameRate) !@This() {
        var self: @This() = .{
            .codec = findBestCodec() catch |err| {
                common.print("Error finding codec: H264\n", .{});
                return err;
            },
            .context = undefined,
        };

        try self.initialize(resolution, frame_rate);
        return self;
    }

    pub fn initialize(self: *@This(), resolution: common.Resolution, frame_rate: common.FrameRate) !void {
        self.context = blk: {
            const context = ffmpeg.avcodec_alloc_context3(self.codec);
            if (context == null) {
                return error.CouldNotAllocateCodecContext;
            }
            break :blk context;
        };
        errdefer ffmpeg.avcodec_free_context(@ptrCast(&self.context));

        self.context.*.width = @intCast(resolution.getResolutionWidth());
        self.context.*.height = @intCast(@intFromEnum(resolution));
        self.context.*.time_base = .{ .num = 1, .den = @intCast(@intFromEnum(frame_rate)) };
        self.context.*.framerate = .{ .num = @intCast(@intFromEnum(frame_rate)), .den = 1 };
        self.context.*.pix_fmt = ffmpeg.AV_PIX_FMT_YUV420P;
        self.context.*.bit_rate = @intCast(common.getMegaBitRate(resolution, frame_rate) * 1024 * 1024);

        if (ffmpeg.avcodec_open2(self.context, self.codec, null) < 0) {
            return error.CouldNotOpenCodec;
        }
    }

    pub fn deinit(self: *@This()) void {
        ffmpeg.avcodec_free_context(@ptrCast(&self.context));
    }

    pub fn submitFrame(self: *@This(), frame: ?*ffmpeg.AVFrame) !void {
        const ret = ffmpeg.avcodec_send_frame(self.context, frame);
        if (ret < 0) {
            return error.CouldNotSendFrame;
        }
    }

    pub fn receivePacket(self: *@This(), packet: *ffmpeg.AVPacket) !bool {
        const ret = ffmpeg.avcodec_receive_packet(self.context, packet);
        if (ret == ffmpeg.AVERROR(ffmpeg.EAGAIN) or ret == ffmpeg.AVERROR_EOF) {
            return false;
        } else if (ret < 0) {
            return error.CouldNotReceivePacket;
        }

        return true;
    }
};
