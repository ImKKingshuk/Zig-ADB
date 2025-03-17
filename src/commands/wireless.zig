//! This module implements the wireless debugging commands for Zig-ADB.

const std = @import("std");
const protocol = @import("../protocol.zig");
const device = @import("../device.zig");
const transport = @import("../transport.zig");
const Command = @import("../commands.zig").Command;
const config = @import("../config.zig");

/// Connect command - connects to a device over TCP/IP
pub const ConnectCommand = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    device_name: ?[]const u8,
    config_ptr: ?*config.Config,

    /// Initialize a new connect command
    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16, device_name: ?[]const u8, config_ptr: ?*config.Config) !ConnectCommand {
        return ConnectCommand{
            .allocator = allocator,
            .host = try allocator.dupe(u8, host),
            .port = port,
            .device_name = if (device_name) |name| try allocator.dupe(u8, name) else null,
            .config_ptr = config_ptr,
        };
    }

    /// Deinitialize the connect command
    pub fn deinit(self: *ConnectCommand) void {
        self.allocator.free(self.host);
        if (self.device_name) |name| {
            self.allocator.free(name);
        }
    }

    /// Create a Command interface from this implementation
    pub fn asCommand(self: *ConnectCommand) Command {
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
        const self: *ConnectCommand = @ptrCast(ctx);

        // Build the connect command
        var cmd_buffer = std.ArrayList(u8).init(allocator);
        defer cmd_buffer.deinit();

        try cmd_buffer.appendSlice("host:connect:");
        try cmd_buffer.appendSlice(self.host);
        try cmd_buffer.append(':');

        var port_buf: [6]u8 = undefined;
        const port_str = try std.fmt.bufPrint(&port_buf, "{d}", .{self.port});
        try cmd_buffer.appendSlice(port_str);

        // Send the command
        const header = protocol.MessageHeader.init(.OPEN, 0, 0, cmd_buffer.items.len);
        try transport_ptr.send(header, cmd_buffer.items);

        // Receive the response
        const response = try transport_ptr.receive(allocator);
        defer if (response.data) |data| allocator.free(data);

        if (response.header.command != .OKAY) {
            return protocol.Error.CommandFailed;
        }

        // Save to config if requested
        if (self.config_ptr != null and self.device_name != null) {
            try self.config_ptr.?.addWirelessDevice(self.device_name.?, try std.fmt.allocPrint(allocator, "{s}:{d}", .{ self.host, self.port }));
        }

        // Print success message
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Connected to {s}:{d}\n", .{ self.host, self.port });
    }

    /// Deinit wrapper implementation
    fn deinitWrapper(ctx: *anyopaque) void {
        const self: *ConnectCommand = @ptrCast(ctx);
        self.deinit();
    }
};

/// Disconnect command - disconnects from a wireless device
pub const DisconnectCommand = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    config_ptr: ?*config.Config,

    /// Initialize a new disconnect command
    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16, config_ptr: ?*config.Config) !DisconnectCommand {
        return DisconnectCommand{
            .allocator = allocator,
            .host = try allocator.dupe(u8, host),
            .port = port,
            .config_ptr = config_ptr,
        };
    }

    /// Deinitialize the disconnect command
    pub fn deinit(self: *DisconnectCommand) void {
        self.allocator.free(self.host);
    }

    /// Create a Command interface from this implementation
    pub fn asCommand(self: *DisconnectCommand) Command {
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
        const self: *DisconnectCommand = @ptrCast(ctx);

        // Build the disconnect command
        var cmd_buffer = std.ArrayList(u8).init(allocator);
        defer cmd_buffer.deinit();

        try cmd_buffer.appendSlice("host:disconnect:");
        try cmd_buffer.appendSlice(self.host);
        try cmd_buffer.append(':');

        var port_buf: [6]u8 = undefined;
        const port_str = try std.fmt.bufPrint(&port_buf, "{d}", .{self.port});
        try cmd_buffer.appendSlice(port_str);

        // Send the command
        const header = protocol.MessageHeader.init(.OPEN, 0, 0, cmd_buffer.items.len);
        try transport_ptr.send(header, cmd_buffer.items);

        // Receive the response
        const response = try transport_ptr.receive(allocator);
        defer if (response.data) |data| allocator.free(data);

        if (response.header.command != .OKAY) {
            return protocol.Error.CommandFailed;
        }

        // Print success message
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Disconnected from {s}:{d}\n", .{ self.host, self.port });
    }

    /// Deinit wrapper implementation
    fn deinitWrapper(ctx: *anyopaque) void {
        const self: *DisconnectCommand = @ptrCast(ctx);
        self.deinit();
    }
};
