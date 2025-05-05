const std = @import("std");
const Crc = std.hash.crc.Crc32Iscsi;

const common = @import("../common/common.zig");

pub const UdpSenderPacket = struct {
    pub const MAX_DATA_SIZE = 1 * 1024;
    pub const Header = struct {
        id: u64,
        no_of_splits: u8,
        parent_offset: u8,
        size: u16,
        crc: u32,

        is_key_frame: bool,
        generated_timestamp: i64,
        resolution: common.Resolution,
        frame_rate: common.FrameRate,
        frame_number: u64,

        pub const empty: @This() = .{
            .id = 0,
            .no_of_splits = 0,
            .parent_offset = 0,
            .is_key_frame = false,
            .generated_timestamp = 0,
            .resolution = .@"360p",
            .frame_rate = .@"30",
            .size = 0,
            .crc = 0,
            .frame_number = 0,
        };

        pub fn format(
            self: Header,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            try writer.print(
                "Header {{ id: {}, splits: {}, offset: {}, size: {}, crc: {x}, key: {}, ts: {}, res: {}, fps: {} }}",
                .{ self.id, self.no_of_splits, self.parent_offset, self.size, self.crc, self.is_key_frame, self.generated_timestamp, self.resolution, self.frame_rate },
            );
        }
    };

    header: Header,
    data: [MAX_DATA_SIZE]u8,

    pub const empty: @This() = .{
        .header = .empty,
        .data = std.mem.zeroes([MAX_DATA_SIZE]u8),
    };

    pub fn initializeCrc(self: *@This()) void {
        self.header.crc = 0;

        const header_ptr = @as([*]const u8, @ptrCast(&self.header));
        const header_size = @sizeOf(@This().Header);

        var crc: Crc = .init();
        crc.update(header_ptr[0..header_size]);

        crc.update(@ptrCast(self.data[0..]));

        self.header.crc = crc.final();
    }

    pub fn is_valid(self: *@This()) bool {
        const current_crc = self.header.crc;
        self.initializeCrc();
        return self.header.crc == current_crc;
    }

    pub fn serialize(self: *const @This(), buffer: []u8) usize {
        const header_ptr = @as([*]const u8, @ptrCast(&self.header));
        const header_size = @sizeOf(@This().Header);
        std.debug.assert(header_size == 40);

        @memcpy(buffer[0..header_size], header_ptr[0..header_size]);
        @memcpy(buffer[header_size .. header_size + self.header.size], self.data[0..self.header.size]);

        return header_size + self.header.size;
    }

    pub fn deserialize(
        self: *@This(),
        buffer: []u8,
    ) void {
        const header_ptr = @as([*]u8, @ptrCast(&self.header));
        const header_size = @sizeOf(@This().Header);

        @memcpy(header_ptr[0..header_size], buffer[0..header_size]);

        if (header_size + self.header.size > buffer.len) {
            return;
        }

        @memcpy(self.data[0..self.header.size], buffer[header_size .. header_size + self.header.size]);
    }
};

pub const UdpReceiverPacket = struct {
    pub const MAX_NUMBER_OF_NACKS = 128;
    pub const Header = struct {
        no_of_nacks: u8,
        new_resolution: common.Resolution,
        new_frame_rate: common.FrameRate,
        stop: bool,
        crc: u32,
        // _padding: [4]u8 = .{ 0, 0, 0, 0 },
    };

    header: Header,
    nacks: [MAX_NUMBER_OF_NACKS]u64,

    pub fn initializeCrc(self: *@This()) void {
        self.header.crc = 0;

        const header_ptr = @as([*]const u8, @ptrCast(&self.header));
        const header_size = @sizeOf(@This().Header);

        var crc: Crc = .init();
        crc.update(header_ptr[0..header_size]);
        crc.update(@ptrCast(self.nacks[0..]));

        self.header.crc = crc.final();
    }

    pub fn is_valid(self: *@This()) bool {
        const current_crc = self.header.crc;
        self.initializeCrc();
        return self.header.crc == current_crc;
    }

    pub fn serialize(self: *const @This(), buffer: []u8) usize {
        const header_ptr = @as([*]const u8, @ptrCast(&self.header));
        const header_size = @sizeOf(@This().Header);

        const nack_size: usize = @sizeOf(u64) * @as(usize, @intCast(self.header.no_of_nacks));
        @memcpy(buffer[0..header_size], header_ptr[0..header_size]);
        @memcpy(
            buffer[header_size .. header_size + nack_size],
            @as([]const u8, @ptrCast(self.nacks[0..self.header.no_of_nacks])),
        );
        return header_size + nack_size;
    }

    pub fn deserialize(
        self: *@This(),
        buffer: []u8,
    ) void {
        const header_ptr = @as([*]u8, @ptrCast(&self.header));
        const header_size = @sizeOf(@This().Header);
        @memcpy(header_ptr[0..header_size], buffer[0..header_size]);

        const nack_size: usize = @sizeOf(u64) * @as(usize, @intCast(self.header.no_of_nacks));
        if (header_size + nack_size > buffer.len) {
            return;
        }
        @memcpy(
            @as([]u8, @ptrCast(self.nacks[0..self.header.no_of_nacks])),
            buffer[header_size .. header_size + nack_size],
        );
    }
};
