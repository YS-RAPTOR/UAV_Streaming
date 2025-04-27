const ffmpeg = @import("ffmpeg");
const std = @import("std");

pub const MP4 = struct {
    context: *ffmpeg.AVFormatContext,
    stream: *ffmpeg.AVStream,

    pub fn init(filename: []const u8, codec_context: *ffmpeg.AVCodecContext) !@This() {
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

        ret = ffmpeg.avcodec_parameters_from_context(stream.*.codecpar, codec_context);
        if (ret < 0) {
            return error.CouldNotCopyCodecParameters;
        }
        stream.*.time_base = codec_context.*.time_base;
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

        return .{
            .context = context,
            .stream = stream,
        };
    }

    pub fn deinit(self: *@This()) void {
        _ = ffmpeg.av_write_trailer(self.context);
        _ = ffmpeg.avio_closep(&self.context.*.pb);
        ffmpeg.avformat_free_context(@ptrCast(self.context));
    }

    pub fn write(self: *@This(), packet: *ffmpeg.AVPacket) !void {
        packet.*.stream_index = self.stream.*.index;
        const ret = ffmpeg.av_interleaved_write_frame(self.context, packet);
        if (ret < 0) {
            return error.CouldNotWriteFrame;
        }
    }
};
