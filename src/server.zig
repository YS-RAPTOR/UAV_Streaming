const std = @import("std");

pub fn main() void {
    std.debug.print("Hello, Client!\n", .{});
}

test "First" {
    try std.testing.expectEqual(1, 1);
}
