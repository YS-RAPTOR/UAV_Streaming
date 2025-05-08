const std = @import("std");

pub fn Queue(comptime T: type, comptime Size: comptime_int) type {
    return struct {
        data: []T,
        head: std.atomic.Value(u8),
        tail: std.atomic.Value(u8),

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{
                .data = try allocator.alloc(T, Size),
                .head = .init(0),
                .tail = .init(0),
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.data);
        }

        pub fn append(self: *@This(), item: T) !void {
            const current_tail = self.tail.load(.unordered);
            const next_tail = (current_tail + 1) % Size;

            if (next_tail == self.head.load(.acquire)) {
                return error.QueueFull;
            }

            self.data[current_tail] = item;
            self.tail.store(next_tail, .release);
        }

        pub fn pop(self: *@This()) ?T {
            const current_head = self.head.load(.unordered);

            if (current_head == self.tail.load(.acquire)) {
                return null; // Queue is empty
            }

            const item = self.data[current_head];
            self.head.store((current_head + 1) % Size, .release);
            return item;
        }
    };
}
