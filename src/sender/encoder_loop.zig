const SharedMemory = @import("shared.zig").SharedMemory;
const source = @import("source.zig");
const common = @import("../common/common.zig");
const std = @import("std");
const ffmpeg = @import("ffmpeg");
const encoder = @import("../common/encoder.zig");

pub const SupportedTypes = enum {
    Test,
    EncodedCamera,
};

pub const EncoderLoop = union(SupportedTypes) {
    Test: TestEncoderLoop,
    EncodedCamera: EncodedCameraLoop,

    pub fn init(
        supported_type: SupportedTypes,
        shared_memory: *SharedMemory,
        resolution: common.Resolution,
        frame_rate: common.FrameRate,
        device: []const u8,
    ) !@This() {
        switch (supported_type) {
            .Test => {
                return .{
                    .Test = try .init(
                        shared_memory,
                        resolution,
                        frame_rate,
                    ),
                };
            },
            .EncodedCamera => {
                return .{
                    .EncodedCamera = try .init(
                        shared_memory,
                        resolution,
                        frame_rate,
                        device,
                    ),
                };
            },
        }
    }

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            inline else => |*ptr| ptr.deinit(),
        }
    }

    pub fn run(self: *@This()) !void {
        switch (self.*) {
            inline else => |*ptr| try ptr.run(),
        }
    }
};

const TestEncoderLoop = struct {
    shared_memory: *SharedMemory,
    source: source.TestSource,
    frame: common.Frame,
    packet: common.Packet,
    true_frame_count: u64,
    frame_no: u64,
    scaler: *ffmpeg.SwsContext,
    scaled_frame: common.Frame,
    encoder: encoder.H264Codec,

    resolution: common.Resolution,
    frame_rate: common.FrameRate,

    fn init(shared_memory: *SharedMemory, resolution: common.Resolution, frame_rate: common.FrameRate) !@This() {
        const scaled_frame = try common.Frame.init();
        scaled_frame.frame.width = resolution.getResolutionWidth();
        scaled_frame.frame.height = @intFromEnum(resolution);
        scaled_frame.frame.format = ffmpeg.AV_PIX_FMT_YUV420P;

        return .{
            .shared_memory = shared_memory,
            .source = try .init(.@"1080p", .@"60"),
            .frame = try .init(),
            .packet = try .init(),
            .true_frame_count = 0,
            .frame_no = 0,
            .scaler = ffmpeg.sws_getContext(
                1920,
                1080,
                ffmpeg.AV_PIX_FMT_YUV420P,
                scaled_frame.frame.width,
                scaled_frame.frame.height,
                scaled_frame.frame.format,
                ffmpeg.SWS_FAST_BILINEAR,
                null,
                null,
                null,
            ) orelse return error.CouldNotAllocateScaler,
            .scaled_frame = scaled_frame,
            .resolution = resolution,
            .frame_rate = frame_rate,
            .encoder = try .init(resolution, frame_rate),
        };
    }

    fn deinit(self: *@This()) void {
        self.source.deinit();
        self.frame.deinit();
        self.packet.deinit();
        self.scaled_frame.deinit();

        ffmpeg.sws_freeContext(self.scaler);
    }

    fn reinitialize(self: *@This(), resolution: common.Resolution) !void {
        self.scaled_frame.deinit();
        self.scaled_frame = try .init();

        self.scaled_frame.frame.width = resolution.getResolutionWidth();
        self.scaled_frame.frame.height = @intFromEnum(resolution);
        self.scaled_frame.frame.format = ffmpeg.AV_PIX_FMT_YUV420P;

        // Flush the encoder
        try self.submitFrame(null);

        // Reinitialize the encoder
        self.encoder.deinit();
        try self.encoder.initialize(resolution, .@"60");
        self.resolution = resolution;
    }

    fn run(self: *@This()) !void {
        errdefer self.shared_memory.crash();
        // Wait for the transfer loop to start
        while (!self.shared_memory.isRunning()) {}
        common.print("Starting Video Encode...\n", .{});

        while (self.shared_memory.isRunning()) {
            const current_time = std.time.microTimestamp();
            defer {
                const fps_60_time_ns: i64 = 1000 * 1000 * 1000 / 60;
                const duration = (std.time.microTimestamp() - current_time) * 1000;
                if (duration < fps_60_time_ns) {
                    std.Thread.sleep(@intCast(fps_60_time_ns - duration));
                }
            }

            {
                const settings = self.shared_memory.getSettings();

                if (self.frame_rate != settings.frame_rate) {
                    std.debug.print("Changing Frame Rate to: {}", .{@intFromEnum(settings.frame_rate)});
                }

                self.frame_rate = settings.frame_rate;
                if (self.resolution != settings.resolution) {
                    std.debug.print("Changing Resolution to {}", .{@intFromEnum(settings.resolution)});
                    try self.reinitialize(settings.resolution);
                }
            }

            const frame = try self.frame.start();
            defer self.frame.end();

            try self.source.fillFrame(frame);

            if (self.frame_rate == .@"30" and self.true_frame_count % 2 == 0) {
                self.true_frame_count +%= 1;
                continue;
            }

            self.scaler = ffmpeg.sws_getCachedContext(
                self.scaler,
                1920,
                1080,
                ffmpeg.AV_PIX_FMT_YUV420P,
                self.resolution.getResolutionWidth(),
                @intFromEnum(self.resolution),
                ffmpeg.AV_PIX_FMT_YUV420P,
                ffmpeg.SWS_FAST_BILINEAR,
                null,
                null,
                null,
            ) orelse return error.CouldNotAllocateScaler;

            const scaled_frame = try self.scaled_frame.start();
            defer self.scaled_frame.end();

            if (ffmpeg.sws_scale_frame(self.scaler, scaled_frame, frame) < 0) {
                return error.ScalerCouldNotScaleFrame;
            }
            scaled_frame.pts = frame.*.pts;
            scaled_frame.pkt_dts = frame.*.pkt_dts;

            try self.submitFrame(scaled_frame);
        }
    }

    fn submitFrame(self: *@This(), frame: ?*ffmpeg.AVFrame) !void {
        var packet = try self.packet.start();
        defer self.packet.end();

        try self.encoder.submitFrame(frame);
        while (try self.encoder.receivePacket(packet)) {
            var data: []u8 = undefined;
            data.len = @intCast(packet.size);
            data.ptr = packet.data;

            self.shared_memory.insertPackets(data, .{
                .id = 0,
                .no_of_splits = 0,
                .parent_offset = 0,
                .size = 0,
                .crc = 0,

                .is_key_frame = (packet.flags & ffmpeg.AV_PKT_FLAG_KEY) != 0,
                .generated_timestamp = std.time.milliTimestamp(),
                .resolution = self.resolution,
                .frame_rate = self.frame_rate,
                .frame_number = self.frame_no,
            });
            self.frame_no +%= 1;
            self.true_frame_count +%= 1;

            self.packet.end();
            packet = try self.packet.start();
        }
    }
};

const EncodedCameraLoop = struct {
    fn init(
        shared_memory: *SharedMemory,
        resolution: common.Resolution,
        frame_rate: common.FrameRate,
        device: []const u8,
    ) !@This() {
        _ = shared_memory;
        _ = resolution;
        _ = frame_rate;
        _ = device;
        return error.NotImplemented;
    }

    fn deinit(self: *@This()) void {
        _ = self;
    }

    fn run(self: *@This()) !void {
        _ = self;
    }
};
