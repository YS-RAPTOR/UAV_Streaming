const ffmpeg = @import("ffmpeg");
const encoder = @import("../common/encoder.zig");
const common = @import("../common/common.zig");
const std = @import("std");

pub const MP4 = struct {
    encoder: encoder.H264Codec,
    context: *ffmpeg.AVFormatContext,
    stream: *ffmpeg.AVStream,
    packet: common.Packet,
    scaler: *ffmpeg.SwsContext,
    frame: common.Frame,

    pub fn init(filename: []const u8) !@This() {
        const resolution = common.Resolution.@"1080p";
        const frame_rate = common.FrameRate.@"60";

        const enc: encoder.H264Codec = try .init(resolution, frame_rate);

        var context: [*c]ffmpeg.AVFormatContext = null;
        var ret = ffmpeg.avformat_alloc_output_context2(
            &context,
            null,
            "mp4",
            filename.ptr,
        );

        if (context == null or ret < 0) {
            return error.CouldNotAllocateOutputContext;
        }
        errdefer ffmpeg.avformat_free_context(context);

        const stream = ffmpeg.avformat_new_stream(context, null);
        if (stream == null) {
            return error.CouldNotAllocateStream;
        }

        ret = ffmpeg.avcodec_parameters_from_context(stream.*.codecpar, enc.context);
        if (ret < 0) {
            return error.CouldNotCopyCodecParameters;
        }
        stream.*.time_base = enc.context.*.time_base;
        stream.*.codecpar.*.codec_tag = 0;

        if ((context.*.oformat.*.flags & ffmpeg.AVFMT_NOFILE) == 0) {
            ret = ffmpeg.avio_open(&context.*.pb, filename.ptr, ffmpeg.AVIO_FLAG_WRITE);
            if (ret < 0) {
                return error.CouldNotOpenOutputFile;
            }
        }

        ret = ffmpeg.avformat_write_header(context, null);
        if (ret < 0) {
            return error.CouldNotWriteHeader;
        }

        const scaler = ffmpeg.sws_getContext(
            resolution.getResolutionWidth(),
            @intFromEnum(resolution),
            ffmpeg.AV_PIX_FMT_NV12,
            resolution.getResolutionWidth(),
            @intFromEnum(resolution),
            ffmpeg.AV_PIX_FMT_YUV420P,
            ffmpeg.SWS_FAST_BILINEAR,
            null,
            null,
            null,
        ) orelse return error.ScalerCouldNotBeInitialize;
        errdefer ffmpeg.sws_freeContext(scaler);

        const frame = try common.Frame.init();
        frame.frame.*.width = resolution.getResolutionWidth();
        frame.frame.*.height = @intFromEnum(resolution);
        frame.frame.*.format = ffmpeg.AV_PIX_FMT_YUV420P;

        return .{
            .encoder = enc,
            .context = context,
            .stream = stream,
            .packet = try .init(),
            .scaler = scaler,
            .frame = try .init(),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.encoder.deinit();
        self.packet.deinit();
        self.frame.deinit();
        _ = ffmpeg.sws_freeContext(self.scaler);
        _ = ffmpeg.av_write_trailer(self.context);
        _ = ffmpeg.avio_closep(&self.context.*.pb);
        ffmpeg.avformat_free_context(@ptrCast(self.context));
    }

    pub fn write(self: *@This(), frame: *ffmpeg.AVFrame) !void {
        const resolution = common.Resolution.@"1080p";

        const scaled_frame = try self.frame.start();
        defer self.frame.end();

        self.scaler = ffmpeg.sws_getCachedContext(
            self.scaler,
            frame.*.width,
            frame.*.height,
            frame.*.format,
            resolution.getResolutionWidth(),
            @intFromEnum(resolution),
            ffmpeg.AV_PIX_FMT_YUV420P,
            ffmpeg.SWS_FAST_BILINEAR,
            null,
            null,
            null,
        ) orelse return error.ScalerCouldNotBeInitialize;

        if (ffmpeg.sws_scale_frame(self.scaler, scaled_frame, frame) < 0) {
            return error.ScalerCouldNotScaleFrame;
        }

        scaled_frame.*.pts = frame.*.pts;
        scaled_frame.*.pkt_dts = frame.*.pkt_dts;

        try self.encoder.submitFrame(scaled_frame);
        const packet = try self.packet.start();

        while (try self.encoder.receivePacket(packet)) {
            packet.*.stream_index = self.stream.*.index;
            const ret = ffmpeg.av_interleaved_write_frame(self.context, packet);
            if (ret < 0) {
                return error.CouldNotWriteFrame;
            }
            self.packet.end();
        }

        if (!self.packet.unref) {
            self.packet.end();
        }
    }
};
