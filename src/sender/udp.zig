const std = @import("std");
const Crc = std.hash.crc.Crc32Iscsi;

const common = @import("../common/common.zig");

pub const UdpSendPacket = struct {
    pub const MAX_DATA_SIZE = 32 * 1024;
    pub const Header = struct {
        id: u64,
        no_of_splits: u8,
        parent_offset: u8,
        size: u16,
        crc: u32,

        is_key_frame: bool,
        generated_timestamp: u64,
        resolution: common.Resolution,
        frame_rate: common.FrameRate,

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
                .{
                    self.id,
                    self.no_of_splits,
                    self.parent_offset,
                    self.size,
                    self.crc,
                    self.is_key_frame,
                    self.generated_timestamp,
                    self.resolution,
                    self.frame_rate,
                },
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
        const struct_ptr = @as([*]const u8, @ptrCast(self));
        const size = @sizeOf(@This());
        self.header.crc = Crc.hash(struct_ptr[0..size]);
    }

    pub fn is_valid(self: *@This()) bool {
        const current_crc = self.header.crc;
        self.initializeCrc();
        return self.header.crc == current_crc;
    }
};
