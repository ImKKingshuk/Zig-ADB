//! Root module for the Zig-ADB library.
//! This module exports all the necessary components for the ADB implementation.

const std = @import("std");

// Export all the modules
pub const protocol = @import("protocol.zig");
pub const device = @import("device.zig");
pub const transport = @import("transport.zig");
pub const commands = @import("commands.zig");

// For backward compatibility with the test in main.zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

// Tests
test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
