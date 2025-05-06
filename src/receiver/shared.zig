const std = @import("std");
const udp = @import("../common/udp.zig");
const common = @import("../common/common.zig");
const ffmpeg = @import("ffmpeg");

const FramePacket = struct {
    frame_rate: common.FrameRate,
    resolution: common.Resolution,
    timestamp: i64,
    is_key_frame: bool,
    mutex: std.Thread.Mutex,

    packetFrame: union(enum) {
        Packet: *ffmpeg.AVPacket,
        Frame: *ffmpeg.AVFrame,
        None: void,
    },

    pub const empty: @This() = .{
        .frame_rate = .@"30",
        .resolution = .@"360p",
        .timestamp = 0,
        .is_key_frame = false,
        .packetFrame = .None,
        .mutex = .{},
    };

    fn init(self: *@This(), packet: udp.UdpSenderPacket, data: []u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.packetFrame == .Frame) {
            ffmpeg.av_frame_free(@ptrCast(&self.packetFrame.Frame));
        } else if (self.packetFrame == .Packet) {
            unreachable;
        }

        var pkt = ffmpeg.av_packet_alloc();
        if (pkt == null) {
            return error.CouldNotAllocatePacket;
        }
        errdefer ffmpeg.av_packet_free(&pkt);

        const ret = ffmpeg.av_packet_from_data(pkt, data.ptr, @intCast(data.len));
        if (ret != 0) {
            return error.CouldCreatePacketFromData;
        }

        self.packetFrame = .{ .Packet = pkt };
        self.frame_rate = packet.header.frame_rate;
        self.resolution = packet.header.resolution;
        self.timestamp = packet.header.generated_timestamp;
        self.is_key_frame = packet.header.is_key_frame;

        if (self.is_key_frame) {
            self.packetFrame.Packet.flags |= ffmpeg.AV_PKT_FLAG_KEY;
        }
    }

    fn deinit(self: *@This()) void {
        if (self.packetFrame == .Frame) {
            ffmpeg.av_frame_free(@ptrCast(&self.packetFrame.Frame));
        } else if (self.packetFrame == .Packet) {
            ffmpeg.av_packet_free(@ptrCast(&self.packetFrame.Packet));
        }
    }
};
const FramePacketBuffer = struct {
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

    fn addPacket(self: *@This(), packets: []udp.UdpSenderPacket, total_size: usize) !void {
        // Add packet to buffer
        var buffer: []u8 = try std.heap.c_allocator.alloc(u8, total_size);
        var start_index: usize = 0;

        for (packets) |packet| {
            @memcpy(buffer[start_index .. start_index + packet.header.size], packet.data[0..packet.header.size]);
            start_index += packet.header.size;
        }
        const index = self.getIndex(packets[0].header.frame_number);
        try self.array.items[index].init(packets[0], buffer);
    }

    pub fn getFramePacket(self: *@This(), id: u64) ?FramePacket {
        // Get the frame packet at the given index
        const index = self.getIndex(id);
        const packet = self.array.items[index];

        if (!packet.mutex.tryLock()) {
            return null;
        }

        return packet;
    }
};

pub const SharedMemory = struct {
    is_stopping: std.atomic.Value(bool),
    frame_packet_buffer: FramePacketBuffer,
    allocator: std.mem.Allocator,
    no_of_frames_received: std.atomic.Value(u64),

    key_frames: std.ArrayListUnmanaged(u64),
    key_frames_mutex: std.Thread.Mutex,

    pub inline fn init(allocator: std.mem.Allocator) !SharedMemory {
        return SharedMemory{
            .is_stopping = std.atomic.Value(bool).init(false),
            .frame_packet_buffer = try .init(allocator, 5),
            .allocator = allocator,
            .key_frames = .empty,
            .key_frames_mutex = .{},
            .no_of_frames_received = .init(0),
        };
    }

    pub inline fn deinit(self: *@This()) void {
        self.frame_packet_buffer.deinit(self.allocator);
    }

    pub fn addPacket(self: *@This(), packets: []udp.UdpSenderPacket) !bool {
        // Add packet to shared memory
        var total_size: usize = 0;
        for (packets) |*packet| {
            if (!packet.is_valid()) {
                return false;
            }
            total_size += packet.header.size;
        }

        if (packets[0].header.frame_number >= 5 * 60 * 60) {
            self.stop();
        }

        try self.frame_packet_buffer.addPacket(packets, total_size);

        if (packets[0].header.is_key_frame) {
            self.key_frames_mutex.lock();
            defer self.key_frames_mutex.unlock();

            try self.key_frames.append(self.allocator, packets[0].header.frame_number);
        }

        _ = self.no_of_frames_received.fetchAdd(1, .unordered);
        return true;
    }

    pub inline fn isStopping(self: *@This()) bool {
        return self.is_stopping.load(.unordered);
    }

    pub inline fn stop(self: *@This()) void {
        self.is_stopping.store(true, .unordered);
    }
};
