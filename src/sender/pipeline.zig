const std = @import("std");
const Packet = @import("ffmpeg").AVPacket;

const source = @import("source.zig");
const encoder = @import("encoder.zig");
const common = @import("../common/common.zig");

pub const SupportedPipelines = enum {
    Test,
    EncodedCamera,
};

pub const Pipeline = union(SupportedPipelines) {
    Test: TestPipeline,
    EncodedCamera: EncodedCameraPipeline,

    pub fn init(pipeline_type: SupportedPipelines, max_resolution: common.Resolution, max_frame_rate: common.FrameRate) !@This() {
        switch (pipeline_type) {
            .Test => |_| return .{
                .Test = try TestPipeline.init(
                    max_resolution,
                    max_frame_rate,
                ),
            },
            .EncodedCamera => |_| return .{
                .EncodedCamera = try EncodedCameraPipeline.init(
                    max_resolution,
                    max_frame_rate,
                ),
            },
        }
    }

    pub fn start(self: *@This(), resolution: common.Resolution, frame_rate: common.FrameRate, submit: bool) !bool {
        switch (self.*) {
            inline else => |*p| return try p.start(resolution, frame_rate, submit),
        }
    }

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            inline else => |*p| p.deinit(),
        }
    }

    pub fn getPacket(self: *@This()) !?*Packet {
        switch (self.*) {
            inline else => |*p| return try p.getPacket(),
        }
    }

    pub fn end(self: *@This()) void {
        switch (self.*) {
            inline else => |*p| p.end(),
        }
    }
};

const TestPipeline = struct {
    source: source.TestSource,
    frame: common.Frame,
    encoder: encoder.H264Codec,
    packet: common.Packet,
    started: bool,
    resolution: common.Resolution,
    frame_rate: common.FrameRate,

    fn init(max_resolution: common.Resolution, max_frame_rate: common.FrameRate) !@This() {
        var frame = try common.Frame.init();
        errdefer frame.deinit();

        var packet = try common.Packet.init();
        errdefer packet.deinit();

        var src = try source.TestSource.init(max_resolution, max_frame_rate);
        errdefer src.deinit();

        var enc = try encoder.H264Codec.init(max_resolution, max_frame_rate);
        errdefer enc.deinit();

        return .{
            .source = src,
            .frame = frame,
            .encoder = enc,
            .packet = packet,
            .started = false,
            .resolution = max_resolution,
            .frame_rate = max_frame_rate,
        };
    }

    fn changeSettings(
        self: *TestPipeline,
        new_resolution: common.Resolution,
        new_frame_rate: common.FrameRate,
    ) !void {
        defer self.frame_rate = new_frame_rate;
        defer self.resolution = new_resolution;
        std.debug.print(
            "New Settings: {s}@{}",
            .{ new_resolution.getResolutionString(), @intFromEnum(new_frame_rate) },
        );
    }

    fn deinit(self: *TestPipeline) void {
        self.source.deinit();
        self.encoder.deinit();
        self.packet.deinit();
        self.frame.deinit();
    }

    fn start(self: *TestPipeline, resolution: common.Resolution, frame_rate: common.FrameRate, submit: bool) !bool {
        if (self.started) {
            unreachable;
        }

        if (resolution != self.resolution or frame_rate != self.frame_rate) {
            try self.changeSettings(resolution, frame_rate);
        }

        self.started = true;
        const f = try self.frame.start();
        errdefer self.frame.end();

        _ = try self.packet.start();
        errdefer self.packet.end();

        if (!try self.source.fillFrame(f)) {
            return false;
        }

        if (submit) {
            try self.encoder.submitFrame(f);
        }
        return true;
    }

    fn getPacket(self: *TestPipeline) !?*Packet {
        if (!self.started) {
            unreachable;
        }
        self.packet.end();
        const p = try self.packet.start();

        if (!try self.encoder.receivePacket(p)) {
            return null;
        }

        return p;
    }

    fn end(self: *TestPipeline) void {
        if (!self.started) {
            unreachable;
        }
        self.frame.end();
        self.packet.end();
        self.started = false;
    }
};

const EncodedCameraPipeline = struct {
    fn init(max_resolution: common.Resolution, max_frame_rate: common.FrameRate) !@This() {
        _ = max_resolution;
        _ = max_frame_rate;
        return .{};
    }

    fn deinit(self: *@This()) void {
        _ = self;
    }

    pub fn start(self: *@This(), resolution: common.Resolution, frame_rate: common.FrameRate, submit: bool) !bool {
        _ = self;
        _ = resolution;
        _ = frame_rate;
        _ = submit;
        return false;
    }

    fn getPacket(self: *@This()) !?*Packet {
        _ = self;
        return null;
    }

    fn end(self: *@This()) void {
        _ = self;
    }
};
