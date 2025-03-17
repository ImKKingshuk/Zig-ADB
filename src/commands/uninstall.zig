//! This module implements the uninstall command for Zig-ADB.

const std = @import("std");
const protocol = @import("../protocol.zig");
const device = @import("../device.zig");
const transport = @import("../transport.zig");
const Command = @import("../commands.zig").Command;

/// Uninstall command - uninstalls an app from the device
pub const UninstallCommand = struct {
    allocator: std.mem.Allocator,
    package_name: []const u8,
    device_serial: ?[]const u8,
    keep_data: bool,

    /// Initialize a new uninstall command
    pub fn init(allocator: std.mem.Allocator, package_name: []const u8, device_serial: ?[]const u8, keep_data: bool) !UninstallCommand {
        return UninstallCommand{
            .allocator = allocator,
            .package_name = try allocator.dupe(u8, package_name),
            .device_serial = if (device_serial) |s| try allocator.dupe(u8, s) else null,
            .keep_data = keep_data,
        };
    }

    /// Deinitialize the uninstall command
    pub fn deinit(self: *UninstallCommand) void {
        self.allocator.free(self.package_name);
        if (self.device_serial) |s| {
            self.allocator.free(s);
        }
    }

    /// Create a Command interface from this implementation
    pub fn asCommand(self: *UninstallCommand) Command {
        return Command{
            .vtable = &.{
                .execute = execute,
                .deinit = deinitWrapper,
            },
            .context = self,
        };
    }

    /// Execute implementation
    fn execute(ctx: *anyopaque, transport_ptr: *transport.Transport, allocator: std.mem.Allocator) protocol.Error!void {
        const self: *UninstallCommand = @ptrCast(ctx);

        // Connect to the device
        try transport_ptr.connect(self.device_serial);
        defer transport_ptr.disconnect();

        // Build the uninstall command
        var cmd_buffer = std.ArrayList(u8).init(allocator);
        defer cmd_buffer.deinit();

        try cmd_buffer.appendSlice("shell:pm uninstall");

        // Add options
        if (self.keep_data) {
            try cmd_buffer.appendSlice(" -k");
        }

        // Add the package name
        try cmd_buffer.append(' ');
        try cmd_buffer.appendSlice(self.package_name);

        // Send the command
        const header = protocol.MessageHeader.init(.OPEN, 0, 0, cmd_buffer.items.len);
        try transport_ptr.send(header, cmd_buffer.items);

        // Receive and process the response
        const stdout = std.io.getStdOut().writer();
        var running = true;
        var success = false;

        while (running) {
            const response = try transport_ptr.receive(allocator);
            defer if (response.data) |data| allocator.free(data);

            switch (response.header.command) {
                .OKAY => {
                    // Connection established, wait for data
                },
                .WRTE => {
                    // Data received
                    if (response.data) |data| {
                        try stdout.writeAll(data);

                        // Check for success message
                        if (std.mem.indexOf(u8, data, "Success")) |_| {
                            success = true;
                        }
                    }
                },
                .CLSE => {
                    // Connection closed
                    running = false;
                },
                else => {
                    return protocol.Error.InvalidResponse;
                },
            }
        }

        if (!success) {
            return protocol.Error.CommandFailed;
        }

        try stdout.print("Successfully uninstalled {s}\n", .{self.package_name});
    }

    /// Deinit wrapper implementation
    fn deinitWrapper(ctx: *anyopaque) void {
        const self: *UninstallCommand = @ptrCast(ctx);
        self.deinit();
    }
};
