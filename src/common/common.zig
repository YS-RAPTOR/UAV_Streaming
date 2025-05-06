const ffmpeg = @import("ffmpeg");
const std = @import("std");

pub const Resolution = enum(u16) {
    @"360p" = 360,
    @"480p" = 480,
    @"720p" = 720,
    @"1080p" = 1080,
    @"1440p" = 1440,
    @"2160p" = 2160,

    pub fn getResolutionString(self: @This()) []const u8 {
        switch (self) {
            .@"360p" => return "640x360",
            .@"480p" => return "854x480",
            .@"720p" => return "1280x720",
            .@"1080p" => return "1920x1080",
            .@"1440p" => return "2560x1440",
            .@"2160p" => return "3840x2160",
        }
    }

    pub fn getResolutionWidth(self: @This()) u16 {
        switch (self) {
            .@"360p" => return 640,
            .@"480p" => return 854,
            .@"720p" => return 1280,
            .@"1080p" => return 1920,
            .@"1440p" => return 2560,
            .@"2160p" => return 3840,
        }
    }
};

pub const FrameRate = enum(u8) {
    @"30" = 30,
    @"60" = 60,

    pub fn getFrameTime(self: *@This(), playback_speed: PlayBackSpeed) i64 {
        switch (playback_speed) {
            .normal => {
                switch (self.*) {
                    .@"30" => return 33,
                    .@"60" => return 16,
                }
            },
            .faster => {
                switch (self.*) {
                    .@"30" => return 22,
                    .@"60" => return 10,
                }
            },
            .fastest => {
                switch (self.*) {
                    .@"30" => return 16,
                    .@"60" => return 8,
                }
            },
        }
    }
};

pub const PlayBackSpeed = enum {
    normal,
    faster,
    fastest,

    pub fn increment(self: *@This()) void {
        switch (self.*) {
            .normal => |_| self = .faster,
            .faster => |_| self = .fastest,
            .fastest => |_| self = .normal,
        }
    }

    pub inline fn getDivisor(self: *@This()) f32 {
        switch (self.*) {
            .normal => return 1,
            .faster => return 1.5,
            .fastest => return 2,
        }
    }
};

// Taken from https://support.google.com/youtube/answer/2853702?hl=en#zippy=%2Ck-p-fps%2Cp-fps%2Cp
pub fn getMegaBitRate(resolution: Resolution, frame_rate: FrameRate) u32 {
    switch (resolution) {
        .@"2160p" => {
            switch (frame_rate) {
                .@"30" => return 30,
                .@"60" => return 35,
            }
        },
        .@"1440p" => {
            switch (frame_rate) {
                .@"30" => return 15,
                .@"60" => return 24,
            }
        },
        .@"1080p" => {
            switch (frame_rate) {
                .@"30" => return 10,
                .@"60" => return 12,
            }
        },
        .@"720p" => {
            switch (frame_rate) {
                .@"30" => return 4,
                .@"60" => return 6,
            }
        },
        else => {
            return 4;
        },
    }
}

pub const Frame = struct {
    frame: *ffmpeg.AVFrame,
    unref: bool,

    pub inline fn init() !@This() {
        const frame = ffmpeg.av_frame_alloc();

        if (frame == null) {
            return error.CouldNotAllocateFrame;
        }

        return .{
            .frame = frame,
            .unref = true,
        };
    }

    pub inline fn deinit(self: *@This()) void {
        ffmpeg.av_frame_free(@ptrCast(&self.frame));
    }

    pub inline fn start(self: *@This()) !*ffmpeg.AVFrame {
        if (self.unref) {
            self.unref = false;
            return self.frame;
        }
        return error.EndFrameBeforeStartingNewFrame;
    }

    pub inline fn end(self: *@This()) void {
        if (self.unref) {
            print("Unref called on already unrefed frame\n", .{});
            unreachable;
        }
        ffmpeg.av_frame_unref(self.frame);
        self.unref = true;
    }
};

pub const Packet = struct {
    packet: *ffmpeg.AVPacket,
    unref: bool,

    pub inline fn init() !@This() {
        const packet = ffmpeg.av_packet_alloc();
        if (packet == null) {
            return error.CouldNotAllocatePacket;
        }

        return .{
            .packet = packet,
            .unref = true,
        };
    }

    pub inline fn deinit(self: *@This()) void {
        ffmpeg.av_packet_free(@ptrCast(&self.packet));
    }

    pub inline fn start(self: *@This()) !*ffmpeg.AVPacket {
        if (self.unref) {
            self.unref = false;
            return self.packet;
        }
        return error.EndpacketBeforeStartingNewpacket;
    }

    pub inline fn end(self: *@This()) void {
        if (self.unref) {
            print("Unref called on already unrefed packet\n", .{});
            unreachable;
        }
        ffmpeg.av_packet_unref(self.packet);
        self.unref = true;
    }
};

pub fn print(comptime fmt: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(fmt, args) catch {
        return;
    };
}

//b - a
pub inline fn wrappedDifference(a: u64, b: u64) u64 {
    return std.math.sub(u64, b, a) catch {
        const subtraction = a - b;
        const half = std.math.maxInt(u64) / 2;
        if (subtraction > half) {
            const b_offsetted = b +% half;
            const a_offsetted = a +% half;
            return b_offsetted - a_offsetted - 1;
        }
        return 0;
    };
}
