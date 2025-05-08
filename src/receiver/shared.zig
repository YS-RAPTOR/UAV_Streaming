const std = @import("std");
const udp = @import("../common/udp.zig");
const common = @import("../common/common.zig");
const ffmpeg = @import("ffmpeg");
const Queue = @import("queue.zig").Queue;

pub const FramePacket = struct {
    frame_rate: common.FrameRate,
    resolution: common.Resolution,
    timestamp: i64,
    is_key_frame: bool,
    mutex: std.Thread.Mutex,

    frame_packet_type: std.atomic.Value(FramePacketType),
    frame_packet: union {
        Packet: *ffmpeg.AVPacket,
        None: void,
    },

    const FramePacketType = enum(u8) {
        Packet,
        PacketWritten,
        None,
    };

    pub const empty: @This() = .{
        .frame_rate = .@"30",
        .resolution = .@"360p",
        .timestamp = 0,
        .is_key_frame = false,
        .frame_packet_type = .init(.None),
        .frame_packet = .{ .None = {} },
        .mutex = .{},
    };

    fn init(self: *@This(), packet: udp.UdpSenderPacket, data: []u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const frame_packet_type = self.frame_packet_type.load(.unordered);
        if (frame_packet_type != .None) {
            std.debug.print("Packet Identifier: {}\n", .{packet.header.frame_number});
            unreachable;
        }

        var pkt = ffmpeg.av_packet_alloc();
        if (pkt == null) {
            return error.CouldNotAllocatePacket;
        }
        errdefer ffmpeg.av_packet_free(&pkt);

        const ret = ffmpeg.av_new_packet(pkt, @intCast(data.len));
        if (ret != 0) {
            return error.CouldNotAllocatePacket;
        }

        @memcpy(pkt.*.data[0..data.len], data);
        pkt.*.size = @intCast(data.len);
        pkt.*.pts = ffmpeg.AV_NOPTS_VALUE;
        pkt.*.dts = ffmpeg.AV_NOPTS_VALUE;
        pkt.*.flags = 0;

        self.frame_packet = .{ .Packet = pkt };
        self.frame_rate = packet.header.frame_rate;
        self.resolution = packet.header.resolution;
        self.timestamp = packet.header.generated_timestamp;
        self.is_key_frame = packet.header.is_key_frame;

        if (self.is_key_frame) {
            self.frame_packet.Packet.flags |= ffmpeg.AV_PKT_FLAG_KEY;
        }
        self.frame_packet.Packet.pts = @bitCast(packet.header.frame_number);

        self.frame_packet_type.store(.Packet, .unordered);
    }

    fn deinit(self: *@This()) void {
        const frame_packet_type = self.frame_packet_type.load(.unordered);
        if (frame_packet_type != .None) {
            ffmpeg.av_packet_free(@ptrCast(&self.frame_packet.Packet));
        }
    }
};

pub const FramePacketBuffer = struct {
    hash_offset: u64,
    array: std.ArrayListUnmanaged(FramePacket),

    fn init(allocator: std.mem.Allocator, comptime storage_time: comptime_int) !@This() {
        const hash_offset, const no_of_frame_packets = comptime blk: {
            const no_of_frame_packets: comptime_int = storage_time * 60 * 60;
            const max_id = std.math.maxInt(u64) + 1;
            const div = max_id / no_of_frame_packets;

            break :blk .{ (div + 1) * no_of_frame_packets - max_id, no_of_frame_packets };
        };

        var array: std.ArrayListUnmanaged(FramePacket) = try .initCapacity(allocator, no_of_frame_packets);
        array.appendNTimesAssumeCapacity(.empty, no_of_frame_packets);

        return .{
            .hash_offset = @intCast(hash_offset),
            .array = array,
        };
    }

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (self.array.items) |*packet| {
            packet.deinit();
        }
        self.array.deinit(allocator);
    }

    fn getIndex(self: *@This(), id: u64) usize {
        // Get the frame packet at the given index
        return (id + self.hash_offset) % self.array.items.len;
    }

    fn addPacket(self: *@This(), allocator: std.mem.Allocator, packets: []udp.UdpSenderPacket, total_size: usize) !void {
        // Add packet to buffer
        var buffer: []u8 = try allocator.alloc(u8, total_size);
        defer allocator.free(buffer);

        var start_index: usize = 0;

        for (packets) |packet| {
            @memcpy(buffer[start_index .. start_index + packet.header.size], packet.data[0..packet.header.size]);
            start_index += packet.header.size;
        }
        const index = self.getIndex(packets[0].header.frame_number);
        try self.array.items[index].init(packets[0], buffer);
    }

    pub fn getFramePacket(self: *@This(), id: u64, frame_packet_type: FramePacket.FramePacketType) ?*FramePacket {
        // Get the frame packet at the given index
        const index = self.getIndex(id);
        var packet = &self.array.items[index];

        if (frame_packet_type != packet.frame_packet_type.load(.unordered)) {
            return null;
        }

        if (!packet.mutex.tryLock()) {
            return null;
        }

        return packet;
    }
};

pub const SharedMemory = struct {
    pub const NumberOfDecoders = 5;

    is_stopping: std.atomic.Value(bool),
    has_crashed: std.atomic.Value(bool),
    frame_packet_buffer: FramePacketBuffer,
    allocator: std.mem.Allocator,
    no_of_frames_received: std.atomic.Value(u64),

    key_frames: [NumberOfDecoders]Queue(u64, 255),
    current_queue: u8,

    pub inline fn init(allocator: std.mem.Allocator) !SharedMemory {
        var keyframes: [NumberOfDecoders]Queue(u64, 255) = undefined;
        for (0..NumberOfDecoders) |i| {
            keyframes[i] = try Queue(u64, 255).init(allocator);
        }

        return SharedMemory{
            .is_stopping = std.atomic.Value(bool).init(false),
            .frame_packet_buffer = try .init(allocator, 5),
            .allocator = allocator,
            .key_frames = keyframes,
            .current_queue = 0,
            .no_of_frames_received = .init(0),
            .has_crashed = .init(false),
        };
    }

    pub inline fn deinit(self: *@This()) void {
        self.frame_packet_buffer.deinit(self.allocator);
        for (0..NumberOfDecoders) |i| {
            self.key_frames[i].deinit(self.allocator);
        }
    }

    pub fn addPacket(self: *@This(), packets: []udp.UdpSenderPacket) !bool {
        // Add packet to shared memory
        var total_size: usize = 0;
        for (packets) |*packet| {
            if (!packet.isValid()) {
                return false;
            }

            total_size += packet.header.size;
        }

        if (packets[0].header.frame_number >= 12500) {
            // std.debug.print("Stopping receiver thread\n", .{});
            self.stop();
        }

        try self.frame_packet_buffer.addPacket(self.allocator, packets, total_size);

        if (packets[0].header.is_key_frame) {
            std.debug.print("Key Frame: {}\n", .{packets[0].header.frame_number});
            try self.key_frames[self.current_queue].append(packets[0].header.frame_number);
            self.current_queue = (self.current_queue + 1) % NumberOfDecoders;
        }

        _ = self.no_of_frames_received.fetchAdd(1, .acq_rel);
        return true;
    }

    pub inline fn isStopping(self: *@This()) bool {
        return self.is_stopping.load(.unordered) or self.has_crashed.load(.unordered);
    }

    pub inline fn stop(self: *@This()) void {
        self.is_stopping.store(true, .unordered);
    }

    pub inline fn hasCrashed(self: *@This()) bool {
        return self.has_crashed.load(.unordered);
    }

    pub inline fn setCrashed(self: *@This()) void {
        self.has_crashed.store(true, .unordered);
    }
};
