const std = @import("std");
const posix = std.posix;
const SharedMemory = @import("shared.zig").SharedMemory;
const udp = @import("../common/udp.zig");

const StopTime = 60 * 1000; // 1 minute = 60s * 1000ms

pub const TransferLoop = struct {
    shared_memory: *SharedMemory,
    current_id: u64,

    nacks: std.AutoArrayHashMapUnmanaged(u64, u1),

    allocator: std.mem.Allocator,
    is_running: bool,
    last_packet_received: i64,

    bind_address: std.net.Address,
    send_address: std.net.Address,

    pub inline fn init(
        alloc: std.mem.Allocator,
        bind_address: []const u8,
        bind_port: u16,
        send_address: []const u8,
        send_port: u16,
        shared_mem: *SharedMemory,
    ) !@This() {
        return .{
            .shared_memory = shared_mem,
            .current_id = shared_mem.current_packet.load(.unordered),

            .nacks = .empty,

            .allocator = alloc,
            .is_running = true,
            .last_packet_received = 0,

            .bind_address = try std.net.Address.parseIp4(bind_address, bind_port),
            .send_address = try std.net.Address.parseIp4(send_address, send_port),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.nacks.deinit(self.allocator);
    }

    pub fn run(self: *@This()) !void {
        defer self.shared_memory.stop();

        var array: std.ArrayListUnmanaged(u8) = try .initCapacity(self.allocator, 70_000);
        array.appendNTimesAssumeCapacity(0, 70_000);
        defer array.deinit(self.allocator);
        const buffer = array.items;

        const socket = try posix.socket(
            posix.AF.INET,
            posix.SOCK.NONBLOCK | posix.SOCK.DGRAM,
            posix.IPPROTO.UDP,
        );
        defer posix.close(socket);
        try posix.bind(socket, @ptrCast(&self.bind_address.un), self.bind_address.getOsSockLen());

        var other_address: posix.sockaddr = undefined;
        var other_address_len: posix.socklen_t = @sizeOf(posix.sockaddr);

        while (!self.shared_memory.isCrashed()) {
            // Try to Receive Packets. If Fails break

            while (true) {
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
                        std.debug.print("Error receiving packet: {}\n", err);
                        return err;
                    }
                };

                var packet: udp.UdpReceiverPacket = undefined;
                packet.deserialize(buffer[0..len]);

                if (!packet.is_valid()) {
                    continue;
                }
                // Modify settings
                self.shared_memory.modifySettings(
                    packet.header.new_resolution,
                    packet.header.new_frame_rate,
                );

                // Stop if stop is set
                if (packet.header.stop) {
                    self.is_running = false;
                    self.shared_memory.stop();
                }

                // Add the packet to the nacks
                for (packet.nacks) |nack| {
                    _ = try self.nacks.getOrPut(self.allocator, nack);
                }
                self.last_packet_received = std.time.milliTimestamp();
            }

            const current_id = self.shared_memory.current_packet.load(.unordered);
            while (self.current_id != current_id) {
                // Try to Send Packets. If fails break

                const packet = self.shared_memory.getPacket(self.current_id);
                const len = packet.serialize(buffer);
                _ = posix.sendto(
                    socket,
                    buffer[0..len],
                    0,
                    @ptrCast(&self.send_address.un),
                    self.send_address.getOsSockLen(),
                ) catch |err| {
                    if (err == error.WouldBlock) {
                        break;
                    } else {
                        std.debug.print("Error sending packet: {}\n", err);
                        return err;
                    }
                };

                self.current_id +%= 1;
            }

            for (self.nacks.keys()) |id| {
                const packet = self.shared_memory.getPacket(id);
                const len = packet.serialize(buffer);
                _ = posix.sendto(
                    socket,
                    buffer[0..len],
                    0,
                    @ptrCast(&self.send_address.un),
                    self.send_address.getOsSockLen(),
                ) catch |err| {
                    if (err == error.WouldBlock) {
                        break;
                    } else {
                        std.debug.print("Error sending packet: {}\n", err);
                        return err;
                    }
                };
            }

            // Have to keep acknowledging nacks
            if (!self.is_running) {
                const current_time = std.time.milliTimestamp();
                if (current_time - self.last_packet_received > StopTime) {
                    break;
                }
            }
        }
    }
};
