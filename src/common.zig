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
    @"24" = 24,
    @"30" = 30,
    @"48" = 48,
    @"60" = 60,
};

// Taken from https://support.google.com/youtube/answer/2853702?hl=en#zippy=%2Ck-p-fps%2Cp-fps%2Cp
pub fn getMegaBitRate(resolution: Resolution, frame_rate: FrameRate) u32 {
    switch (resolution) {
        .@"2160p" => {
            switch (frame_rate) {
                .@"24" => return 29,
                .@"30" => return 30,
                .@"48" => return 33,
                .@"60" => return 35,
            }
        },
        .@"1440p" => {
            switch (frame_rate) {
                .@"24" => return 14,
                .@"30" => return 15,
                .@"48" => return 21,
                .@"60" => return 24,
            }
        },
        .@"1080p" => {
            switch (frame_rate) {
                .@"24" => return 9,
                .@"30" => return 10,
                .@"48" => return 11,
                .@"60" => return 12,
            }
        },
        .@"720p" => {
            switch (frame_rate) {
                .@"24" => return 4,
                .@"30" => return 4,
                .@"48" => return 5,
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
            std.debug.print("Unref called on already unrefed frame\n", .{});
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
            std.debug.print("Unref called on already unrefed packet\n", .{});
            unreachable;
        }
        ffmpeg.av_packet_unref(self.packet);
        self.unref = true;
    }
};
