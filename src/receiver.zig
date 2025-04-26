const std = @import("std");

pub fn main() void {
    std.debug.print("Hello, Client!\n", .{});
    const i: usize = 0;

    const f: f64 = i;
    _ = f;
}

test "First" {
    try std.testing.expectEqual(1, 1);
}
