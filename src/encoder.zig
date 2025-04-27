const ffmpeg = @import("ffmpeg");
const common = @import("common.zig");
const std = @import("std");

pub const H264Codec = struct {
    codec: *const ffmpeg.AVCodec,
    context: *ffmpeg.AVCodecContext,

    fn findBestCodec() !*const ffmpeg.AVCodec {
        var codec = ffmpeg.avcodec_find_encoder_by_name("h264_nvenc");

        if (codec != null) {
            std.debug.print("Using NVENC codec\n", .{});
            return codec;
        }

        codec = ffmpeg.avcodec_find_encoder_by_name("h264_amf");
        if (codec != null) {
            std.debug.print("Using AMF codec\n", .{});
            return codec;
        }

        codec = ffmpeg.avcodec_find_encoder_by_name("h264_qsv");
        if (codec != null) {
            std.debug.print("Using QSV codec\n", .{});
            return codec;
        }

        codec = ffmpeg.avcodec_find_encoder_by_name("h264_v4l2m2m");
        if (codec != null) {
            std.debug.print("Using V4L2M2M codec\n", .{});
            return codec;
        }

        codec = ffmpeg.avcodec_find_encoder(ffmpeg.AV_CODEC_ID_H264);

        if (codec == null) {
            return error.CodecNotFound;
        }
        std.debug.print("Using default H264 codec\n", .{});
        return codec;
    }

    pub fn init(resolution: common.Resolution, frame_rate: common.FrameRate) !@This() {
        const codec = H264Codec.findBestCodec() catch |err| {
            std.debug.print("Error finding codec: H264\n", .{});
            return err;
        };

        var context = ffmpeg.avcodec_alloc_context3(codec);
        if (context == null) {
            return error.CouldNotAllocateCodecContext;
        }

        errdefer ffmpeg.avcodec_free_context(&context);

        context.*.width = @intCast(resolution.getResolutionWidth());
        context.*.height = @intCast(@intFromEnum(resolution));
        context.*.time_base = .{ .num = 1, .den = @intCast(@intFromEnum(frame_rate)) };
        context.*.framerate = .{ .num = @intCast(@intFromEnum(frame_rate)), .den = 1 };
        context.*.pix_fmt = ffmpeg.AV_PIX_FMT_YUV420P;
        context.*.bit_rate = @intCast(common.getMegaBitRate(resolution, frame_rate) * 1024 * 1024);

        // _ = ffmpeg.av_opt_set(context.*.priv_data, "preset", "ultrafast", 0);
        // _ = ffmpeg.av_opt_set(context.*.priv_data, "tune", "zerolatency", 0);

        if (ffmpeg.avcodec_open2(context, codec, null) < 0) {
            return error.CouldNotOpenCodec;
        }

        return .{
            .codec = codec,
            .context = context,
        };
    }

    pub fn deinit(self: *@This()) void {
        ffmpeg.avcodec_free_context(@ptrCast(&self.context));
    }

    const PacketIterator = struct {
        ret: isize,
        context: *ffmpeg.AVCodecContext,
        packet: common.Packet,
        start: bool,

        pub fn init(packet: common.Packet, context: *ffmpeg.AVCodecContext) !@This() {
            return .{
                .ret = 0,
                .context = context,
                .packet = packet,
                .start = false,
            };
        }

        pub inline fn next(self: *@This()) !?*ffmpeg.AVPacket {
            if (self.start) {
                @branchHint(.unlikely);
                self.packet.end();
            }
            self.start = true;

            self.ret = ffmpeg.avcodec_receive_packet(self.context, try self.packet.start());
            if (self.ret == ffmpeg.AVERROR(ffmpeg.EAGAIN) or self.ret == ffmpeg.AVERROR_EOF) {
                return null;
            } else if (self.ret < 0) {
                return error.CouldNotReceivePacket;
            }

            return self.packet.packet;
        }
    };

    pub fn getPackets(self: *@This(), frame: *ffmpeg.AVFrame, packet: common.Packet) !PacketIterator {
        const ret = ffmpeg.avcodec_send_frame(self.context, frame);
        if (ret < 0) {
            return error.CouldNotSendFrame;
        }

        return PacketIterator.init(packet, self.context);
    }
};
