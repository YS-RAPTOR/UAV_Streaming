const std = @import("std");
const SharedMemory = @import("shared.zig").SharedMemory;

pub const TransferLoop = struct {
    shared_memory: *SharedMemory,
    nacks: std.ArrayListUnmanaged(u64),
    allocator: std.mem.Allocator,

    pub fn run(self: *@This()) void {
        _ = self;
    }
};
