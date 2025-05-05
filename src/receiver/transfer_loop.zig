const std = @import("std");
const posix = std.posix;
const SharedMemory = @import("shared.zig").SharedMemory;
const udp = @import("../common/udp.zig");
const common = @import("../common/common.zig");

pub const TransferLoop = struct {
    allocator: std.mem.Allocator,
    bind_address: std.net.Address,
    send_address: std.net.Address,

    nacks: std.AutoArrayHashMapUnmanaged(u64, i64),
    current_id: u64,

    packets: std.AutoArrayHashMapUnmanaged(u64, std.ArrayListUnmanaged(udp.UdpSenderPacket)),
    already_received: std.ArrayListUnmanaged(bool),
    hash_offset: u64,

    shared_memory: *SharedMemory,

    info_buffer: std.ArrayListUnmanaged(Info),
    info_index: usize,
    const Info = struct {
        latency: i64,
        size: u16,
        timestamp: i64,
    };

    pub fn init(
        alloc: std.mem.Allocator,
        bind_address: []const u8,
        bind_port: u16,
        send_address: []const u8,
        send_port: u16,
        shared_mem: *SharedMemory,
    ) !@This() {
        var info_buffer = try std.ArrayListUnmanaged(Info).initCapacity(alloc, 1000);
        info_buffer.appendNTimesAssumeCapacity(.{ .latency = 0, .size = 0, .timestamp = 0 }, 1000);

        var already_received = try std.ArrayListUnmanaged(bool).initCapacity(
            alloc,
            shared_mem.frame_packet_buffer.array.items.len,
        );
        already_received.appendNTimesAssumeCapacity(
            false,
            shared_mem.frame_packet_buffer.array.items.len,
        );

        return .{
            .allocator = alloc,
            .bind_address = try std.net.Address.resolveIp(bind_address, bind_port),
            .send_address = try std.net.Address.resolveIp(send_address, send_port),
            .shared_memory = shared_mem,
            .nacks = .empty,
            .current_id = 0,
            .info_buffer = info_buffer,
            .info_index = 0,
            .packets = .empty,
            .already_received = already_received,
            .hash_offset = shared_mem.frame_packet_buffer.hash_offset,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.nacks.deinit(self.allocator);
        self.info_buffer.deinit(self.allocator);
        self.packets.deinit(self.allocator);
        self.already_received.deinit(self.allocator);
    }

    pub fn run(self: *@This()) !void {
        var array: std.ArrayListUnmanaged(u8) = try .initCapacity(self.allocator, 70_000);
        array.appendNTimesAssumeCapacity(0, 70_000);
        defer array.deinit(self.allocator);
        const buffer = array.items;

        const socket = try posix.socket(
            posix.AF.INET,
            posix.SOCK.DGRAM | posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK,
            0,
        );
        defer posix.close(socket);

        try posix.bind(socket, &self.bind_address.any, self.bind_address.getOsSockLen());
        common.print("Listening...\n", .{});

        while (true) {
            self.receivePackets(socket, buffer) catch |err| {
                common.print("Error receiving packets: {}\n", .{err});
                return err;
            };

            var iterator = self.nacks.iterator();
            while (self.sendPackets(socket, buffer, &iterator) catch |err| {
                common.print("Error sending packets: {}\n", .{err});
                return err;
            }) {}

            // std.debug.print("Nacks: {}\n", .{self.nacks.count()});
            if (self.shared_memory.isStopping() and self.nacks.count() == 0) {
                return;
            }
        }
    }

    inline fn getSubtractionOfIds(self: *@This(), id: u64) u64 {
        return std.math.sub(u64, id, self.current_id) catch {
            const subtraction = self.current_id - id;
            const half = std.math.maxInt(u64) / 2;
            if (subtraction > half) {
                const packet_offsetted = id +% half;
                const current_id_offsetted = self.current_id +% half;
                return packet_offsetted - current_id_offsetted - 1;
            }
            return 0;
        };
    }

    fn receivePackets(self: *@This(), socket: c_int, buffer: []u8) !void {
        var other_address: posix.sockaddr = undefined;
        var other_address_len: posix.socklen_t = @sizeOf(posix.sockaddr);

        for (0..1000) |_| {
            const len = posix.recvfrom(
                socket,
                buffer,
                0,
                &other_address,
                &other_address_len,
            ) catch |err| {
                if (err == error.WouldBlock) {
                    break;
                } else {
                    return err;
                }
            };
            var packet: udp.UdpSenderPacket = undefined;
            packet.deserialize(buffer[0..len]);

            const current_time = std.time.milliTimestamp();
            if (!packet.is_valid()) {
                continue;
            }

            self.insertInfo(
                current_time - packet.header.generated_timestamp,
                @intCast(len),
                current_time,
            );

            // Make sure that the packet received is not older than 3 minutes
            if (current_time - packet.header.generated_timestamp > 3 * 60 * 1000) {
                continue;
            }

            // Remove the packet from the nacks if present
            if (self.nacks.contains(packet.header.id)) {
                _ = self.nacks.fetchSwapRemove(packet.header.id);
            } else {
                // Add packets from current id to the received id to the nacks
                if (self.current_id != packet.header.id) {
                    const iterations = self.getSubtractionOfIds(packet.header.id);
                    for (0..iterations) |_| {
                        _ = try self.nacks.getOrPutValue(self.allocator, self.current_id, current_time);
                        self.current_id +%= 1;
                    }
                    if (iterations > 0) {
                        self.current_id +%= 1;
                    }
                } else {
                    self.current_id +%= 1;
                }
            }

            // Store the packet in the buffer

            const parent_id = packet.header.id - packet.header.parent_offset;
            if (self.hasReceived(parent_id)) {
                continue;
            }

            var results = try self.packets.getOrPut(
                self.allocator,
                parent_id,
            );

            if (results.found_existing) {
                @memcpy(
                    @as([*]u8, @ptrCast(&results.value_ptr.items[packet.header.parent_offset]))[0..@sizeOf(udp.UdpSenderPacket)],
                    @as([*]u8, @ptrCast(&packet))[0..@sizeOf(udp.UdpSenderPacket)],
                );
            } else {
                results.value_ptr.* = .empty;
                try results.value_ptr.appendNTimes(self.allocator, .empty, packet.header.no_of_splits);
                @memcpy(
                    @as([*]u8, @ptrCast(&results.value_ptr.items[packet.header.parent_offset]))[0..@sizeOf(udp.UdpSenderPacket)],
                    @as([*]u8, @ptrCast(&packet))[0..@sizeOf(udp.UdpSenderPacket)],
                );
            }

            if (try self.shared_memory.addPacket(results.value_ptr.items)) {
                var array = self.packets.fetchSwapRemove(parent_id).?;
                array.value.deinit(self.allocator);
                self.setReceived(parent_id);
            }
        }
    }

    pub fn hasReceived(self: *@This(), parent_id: u64) bool {
        const index = (parent_id + self.hash_offset) % self.already_received.items.len;
        return self.already_received.items[index];
    }

    pub fn setReceived(self: *@This(), parent_id: u64) void {
        const index = (parent_id + self.hash_offset) % self.already_received.items.len;
        var half = index + self.already_received.items.len / 2;
        half = half % self.already_received.items.len;

        std.debug.assert(half != index);
        self.already_received.items[index] = true;
        self.already_received.items[half] = false;
    }

    fn sendPackets(self: *@This(), socket: c_int, buffer: []u8, iterator: *@TypeOf(self.nacks).Iterator) !bool {
        const resolution, const frame_rate = adaptiveStreaming(
            self.info_buffer.items,
            self.nacks.count(),
        );

        var packet: udp.UdpReceiverPacket = .{
            .header = .{
                .new_frame_rate = frame_rate,
                .new_resolution = resolution,
                .no_of_nacks = undefined,
                .stop = self.shared_memory.is_stopping.load(.unordered),
                .crc = 0,
            },
            .nacks = undefined,
        };

        const current_time = std.time.milliTimestamp();
        var no_of_nacks: u8 = 0;

        while (iterator.next()) |entry| {
            // If greater than 1000ms add to nacks
            if (current_time - entry.value_ptr.* > 1000) {
                if (no_of_nacks >= packet.nacks.len) {
                    break;
                }
                entry.value_ptr.* = current_time;
                packet.nacks[no_of_nacks] = entry.key_ptr.*;
                no_of_nacks += 1;
            }
        }
        if (no_of_nacks == 0) {
            return false;
        }

        packet.header.no_of_nacks = @intCast(no_of_nacks);
        packet.initializeCrc();

        const len = packet.serialize(buffer);
        _ = posix.sendto(
            socket,
            buffer[0..len],
            0,
            &self.send_address.any,
            self.send_address.getOsSockLen(),
        ) catch |err| {
            if (err == error.WouldBlock) {
                return false;
            } else {
                return err;
            }
        };
        return true;
    }

    inline fn insertInfo(self: *@This(), latency: i64, size: u16, timestamp: i64) void {
        self.info_buffer.items[self.info_index] = Info{
            .latency = latency,
            .size = size,
            .timestamp = timestamp,
        };
        self.info_index += 1;
        self.info_index %= self.info_buffer.items.len;
    }

    fn adaptiveStreaming(info_buffer: []Info, no_of_nacks: usize) struct { common.Resolution, common.FrameRate } {

        // TODO: Fix this code.
        var total_latency: i64 = 0;
        var total_size: u32 = 0;
        var no_of_packets: u32 = 0;

        var smallest_time: i64 = std.math.maxInt(i64);
        var largest_time: i64 = std.math.minInt(i64);

        for (info_buffer) |info| {
            if (info.latency == 0 and info.size == 0) {
                break;
            }
            total_latency += info.latency;
            total_size += info.size;
            no_of_packets += 1;

            smallest_time = @min(smallest_time, info.timestamp);
            largest_time = @max(largest_time, info.timestamp);
        }

        if (no_of_packets != info_buffer.len) {
            return .{
                common.Resolution.@"2160p",
                common.FrameRate.@"60",
            };
        }

        const time_difference: f32 = @floatFromInt(largest_time - smallest_time);
        const average_latency: f32 = @as(f32, @floatFromInt(total_latency)) / @as(f32, @floatFromInt(no_of_packets)); // Milliseconds
        const average_bandwidth: f32 = (@as(f32, @floatFromInt(total_size)) / (time_difference / 1000)) / (1024); // KilloBytes/s

        var resolution: common.Resolution = undefined;
        var frame_rate: common.FrameRate = undefined;

        _ = average_latency;
        // common.print(
        //     "Average Latency: {d} ms/s, Average Bandwidth: {d} KB/s, Number of Nacks: {}\n",
        //     .{ average_latency, average_bandwidth, no_of_nacks },
        // );

        if (no_of_nacks <= 100) {
            frame_rate = common.FrameRate.@"60";
        } else {
            frame_rate = common.FrameRate.@"30";
        }

        // Resolutions_available are 2160p, 1440p, 1080p, 720p, 480p, 360p
        if (average_bandwidth > 1000) {
            resolution = common.Resolution.@"2160p";
        } else if (average_bandwidth > 500) {
            resolution = common.Resolution.@"1440p";
        } else if (average_bandwidth > 250) {
            resolution = common.Resolution.@"1080p";
        } else if (average_bandwidth > 100) {
            resolution = common.Resolution.@"720p";
        } else if (average_bandwidth > 50) {
            resolution = common.Resolution.@"480p";
        } else {
            resolution = common.Resolution.@"360p";
        }

        return .{ resolution, frame_rate };
    }
};
