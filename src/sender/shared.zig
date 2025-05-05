const std = @import("std");
const udp = @import("../common/udp.zig");
const common = @import("../common/common.zig");

pub const SharedMemory = struct {
    allocator: std.mem.Allocator,

    committed_packets: std.ArrayListUnmanaged(udp.UdpSenderPacket),
    hash_offset: u64,

    current_packet: std.atomic.Value(u64),
    settings: std.atomic.Value(Settings),
    running: std.atomic.Value(bool),
    main_thread_crash: std.atomic.Value(bool),

    pub const Settings = packed struct(u32) {
        resolution: common.Resolution,
        frame_rate: common.FrameRate,
        _padding: u8 = 0,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        starting_resolution: common.Resolution,
        starting_frame_rate: common.FrameRate,
        comptime storage: comptime_int,
    ) !SharedMemory {
        const hash_offset, const no_of_udp_packets = comptime blk: {
            const storate_bytes: comptime_float = storage * 1024.0 * 1024.0 * 1024.0;
            const no_of_udp_packets: comptime_int = @intFromFloat(@ceil((storate_bytes / udp.UdpSenderPacket.MAX_DATA_SIZE)));
            const max_id = std.math.maxInt(u64) + 1;
            const div = max_id / no_of_udp_packets;

            break :blk .{ (div + 1) * no_of_udp_packets - max_id, no_of_udp_packets };
        };

        var committed_packets: std.ArrayListUnmanaged(udp.UdpSenderPacket) = .empty;
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
            .running = .init(false),
            .main_thread_crash = .init(false),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.committed_packets.deinit(self.allocator);
    }

    pub inline fn getIndex(self: *@This(), id: u64) u64 {
        return (id + self.hash_offset) % self.committed_packets.items.len;
    }

    pub inline fn insertPackets(self: *@This(), data: []u8, header: udp.UdpSenderPacket.Header) void {
        const no_of_splits = (data.len / udp.UdpSenderPacket.MAX_DATA_SIZE) + 1;
        const chunk_size = data.len / no_of_splits;
        var chunk_remainder = data.len % no_of_splits;

        for (0..no_of_splits) |split| {
            const current_id = self.current_packet.load(.unordered);
            defer self.current_packet.store(current_id +% 1, .unordered);

            const index = self.getIndex(current_id);

            var slice: []u8 = undefined;
            slice.len = chunk_size;
            slice.ptr = data.ptr + chunk_size * split;

            if (chunk_remainder > 0) {
                slice.len += 1;
                chunk_remainder -= 1;
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
    ) udp.UdpSenderPacket {
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

    pub inline fn isRunning(self: *@This()) bool {
        return self.running.load(.unordered);
    }

    pub inline fn stop(self: *@This()) void {
        self.running.store(false, .unordered);
    }

    pub inline fn crash(self: *@This()) void {
        self.main_thread_crash.store(true, .unordered);
    }

    pub inline fn isCrashed(self: *@This()) bool {
        return self.main_thread_crash.load(.unordered);
    }
};
