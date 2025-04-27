const ffmpeg = @import("ffmpeg");
const common = @import("common.zig");

const H264Codec = struct {
    codec: *ffmpeg.AVCodec,
    context: *ffmpeg.AVCodecContext,

    fn init(resolution: common.Resolution, frame_rate: common.FrameRate) !@This() {
        const codec = ffmpeg.avcodec_find_encoder(ffmpeg.AV_CODEC_ID_H264);
        if (codec == null) {
            return error.CodecNotFound;
        }

        const context = ffmpeg.avcodec_alloc_context3(codec);
        context.*.width = @intCast(resolution.getResolutionWidth());
        context.*.height = @intCast(@intFromEnum(resolution));
        context.*.time_base = .{ .num = 1, .den = @intCast(@intFromEnum(frame_rate)) };
        context.*.framerate = .{ .num = @intCast(@intFromEnum(frame_rate)), .den = 1 };
    }
};
