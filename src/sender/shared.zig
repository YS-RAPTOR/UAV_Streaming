const std = @import("std");
const udp = @import("udp.zig");
const common = @import("../common/common.zig");

pub const SharedMemory = struct {
    allocator: std.mem.Allocator,

    committed_packets: std.ArrayListUnmanaged(udp.UdpSendPacket),
    hash_offset: u64,

    current_packet: std.atomic.Value(u64),
    settings: std.atomic.Value(Settings),

    pub const Settings = packed struct(u32) {
        resolution: common.Resolution,
        frame_rate: common.FrameRate,
        _padding: u8 = 0,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        starting_resolution: common.Resolution,
        starting_frame_rate: common.FrameRate,
        comptime storage_time: comptime_int,
    ) !SharedMemory {
        const hash_offset = comptime blk: {
            const no_of_udp_packets = storage_time * 60 * 60 * 3;
            const max_id = std.math.maxInt(u64) + 1;
            const div = max_id / no_of_udp_packets;
            break :blk (div + 1) * no_of_udp_packets - max_id;
        };

        const no_of_udp_packets = storage_time * 60 * 60 * 2;
        var committed_packets: std.ArrayListUnmanaged(udp.UdpSendPacket) = .empty;
        try committed_packets.appendNTimes(allocator, .empty, no_of_udp_packets);
        errdefer committed_packets.deinit(allocator);

        return .{
            .allocator = allocator,
            .committed_packets = committed_packets,
            .current_packet = .init(0),
            .hash_offset = @intCast(hash_offset),
            .settings = .init(.{
                .resolution = starting_resolution,
                .frame_rate = starting_frame_rate,
            }),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.committed_packets.deinit(self.allocator);
    }

    pub inline fn getIndex(self: *@This(), id: u64) u64 {
        return (id + self.hash_offset) % self.committed_packets.items.len;
    }

    pub inline fn insertPackets(self: *@This(), data: []u8, header: udp.UdpSendPacket.Header) void {
        const no_of_splits = data.len / udp.UdpSendPacket.MAX_DATA_SIZE + 1;
        const chunk_size = data.len / no_of_splits;
        const chunk_remainder = data.len % no_of_splits;

        for (0..no_of_splits) |split| {
            const current_id = self.current_packet.load(.unordered);
            defer self.current_packet.store(current_id +% 1, .unordered);

            const index = self.getIndex(current_id);

            var slice: []u8 = undefined;
            slice.len = chunk_size;
            slice.ptr = data.ptr + chunk_size * split;
            if (split == no_of_splits - 1) {
                slice.len += chunk_remainder;
            }

            self.committed_packets.items[index].header = header;
            self.committed_packets.items[index].header.id = current_id;
            self.committed_packets.items[index].header.size = @intCast(slice.len);
            self.committed_packets.items[index].header.no_of_splits = @intCast(no_of_splits);
            self.committed_packets.items[index].header.parent_offset = @intCast(split);

            @memcpy(self.committed_packets.items[index].data[0..slice.len], slice);
            self.committed_packets.items[index].initializeCrc();
        }
    }

    pub inline fn getPacket(
        self: *@This(),
        id: u64,
    ) udp.UdpSendPacket {
        const index = self.getIndex(id);
        return self.committed_packets.items[index];
    }

    pub inline fn modifySettings(
        self: *@This(),
        resolution: common.Resolution,
        frame_rate: common.FrameRate,
    ) void {
        const settings = self.settings.load(.unordered);
        if (settings.frame_rate != frame_rate or settings.resolution != resolution) {
            self.settings.store(.{ .frame_rate = frame_rate, .resolution = resolution }, .unordered);
        }
    }

    pub inline fn getSettings(self: *@This()) Settings {
        return self.settings.load(.unordered);
    }
};
