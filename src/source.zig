const ffmpeg = @import("ffmpeg");
const std = @import("std");
const common = @import("common.zig");

pub const SourceType = enum {
    Test,
    Camera,
};

pub const Source = union(SourceType) {
    Test: TestSource,
    Camera: CameraSource,

    pub fn init(
        source_type: SourceType,
        max_resolution: common.Resolution,
        max_frame_rate: common.FrameRate,
    ) !@This() {
        switch (source_type) {
            .Test => return .{ .Test = try TestSource.init(max_resolution, max_frame_rate) },
            .Camera => return .{ .Camera = try CameraSource.init(max_resolution, max_frame_rate) },
        }
    }

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            inline else => |*source| {
                source.deinit();
            },
        }
    }

    pub fn fillFrame(self: *@This(), frame: common.Frame) !bool {
        switch (self.*) {
            inline else => |*source| {
                return source.fillFrame(frame);
            },
        }
    }
};

const TestSource = struct {
    filter: *ffmpeg.AVFilterGraph,
    source: *ffmpeg.AVFilterContext,
    sink: *ffmpeg.AVFilterContext,

    fn init(max_resolution: common.Resolution, max_frame_rate: common.FrameRate) !@This() {
        var filter_graph = ffmpeg.avfilter_graph_alloc();
        errdefer ffmpeg.avfilter_graph_free(&filter_graph);
        if (filter_graph == null) {
            return error.CouldNotAllocateFilterGraph;
        }

        var buffer: [256]u8 = undefined;
        const filter_description: [*:0]const u8 = try std.fmt.bufPrintZ(
            &buffer,
            "testsrc=size={s}:rate={s}," ++
                "drawtext=font='Arial':" ++
                "text='Time - %{{localtime}} (%{{pts\\:hms}}) Frame \\: %{{n}}':" ++
                "fontsize=48:fontcolor=white:x=10:y=10:" ++
                "box=1:boxcolor=black," ++
                "nullsink",
            .{ max_resolution.getResolutionString(), @tagName(max_frame_rate) },
        );

        var inputs = ffmpeg.avfilter_inout_alloc();
        defer ffmpeg.avfilter_inout_free(&inputs);
        errdefer ffmpeg.avfilter_inout_free(&inputs);

        var outputs = ffmpeg.avfilter_inout_alloc();
        defer ffmpeg.avfilter_inout_free(&outputs);
        errdefer ffmpeg.avfilter_inout_free(&outputs);

        inputs.*.name = ffmpeg.av_strdup("in");
        inputs.*.filter_ctx = null;
        inputs.*.pad_idx = 0;
        inputs.*.next = null;

        outputs.*.name = ffmpeg.av_strdup("out");
        outputs.*.filter_ctx = null;
        outputs.*.pad_idx = 0;
        outputs.*.next = null;

        var ret = ffmpeg.avfilter_graph_parse_ptr(
            filter_graph,
            filter_description,
            &inputs,
            &outputs,
            null,
        );

        if (ret < 0) {
            return error.CouldNotParseFilterGraph;
        }

        ret = ffmpeg.avfilter_graph_config(filter_graph, null);

        if (ret < 0) {
            return error.CouldNotConfigureFilterGraph;
        }

        const source = ffmpeg.avfilter_graph_get_filter(filter_graph, "Parsed_testsrc_0");
        if (source == null) {
            return error.CouldNotGetSourceFilter;
        }

        const sink = ffmpeg.avfilter_graph_get_filter(filter_graph, "Parsed_drawtext_1");
        if (sink == null) {
            return error.CouldNotGetSinkFilter;
        }

        return .{
            .filter = filter_graph,
            .source = source,
            .sink = sink,
        };
    }

    fn fillFrame(self: *@This(), frame: common.Frame) !bool {
        const ret = ffmpeg.av_buffersink_get_frame(self.sink, try frame.start());
        if (ret == ffmpeg.AVERROR(ret) or ret == ffmpeg.AVERROR_EOF) {
            return false;
        } else if (ret < 0) {
            return error.CouldNotGetFrame;
        }
        return true;
    }

    fn deinit(self: *@This()) void {
        ffmpeg.avfilter_graph_free(@ptrCast(&self.filter));
    }
};

const CameraSource = struct {
    fn init(max_resolution: common.Resolution, max_frame_rate: common.FrameRate) !@This() {
        _ = max_resolution;
        _ = max_frame_rate;

        return error.Cringe;
    }

    fn deinit(self: *@This()) void {
        _ = self;
    }
};
