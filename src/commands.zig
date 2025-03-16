//! This module implements the various ADB commands.

const std = @import("std");
const protocol = @import("protocol.zig");
const device = @import("device.zig");
const transport = @import("transport.zig");

/// Base command interface
pub const Command = struct {
    vtable: *const VTable,
    context: *anyopaque,

    pub const VTable = struct {
        execute: *const fn (ctx: *anyopaque, transport_ptr: *transport.Transport, allocator: std.mem.Allocator) protocol.Error!void,
        deinit: *const fn (ctx: *anyopaque) void,
    };

    /// Execute the command
    pub fn execute(self: *Command, transport_ptr: *transport.Transport, allocator: std.mem.Allocator) protocol.Error!void {
        return self.vtable.execute(self.context, transport_ptr, allocator);
    }

    /// Deinitialize the command
    pub fn deinit(self: *Command) void {
        self.vtable.deinit(self.context);
    }
};

/// Devices command - lists connected devices
pub const DevicesCommand = struct {
    allocator: std.mem.Allocator,
    device_manager: *device.DeviceManager,
    long_format: bool,

    /// Initialize a new devices command
    pub fn init(allocator: std.mem.Allocator, device_manager: *device.DeviceManager, long_format: bool) DevicesCommand {
        return DevicesCommand{
            .allocator = allocator,
            .device_manager = device_manager,
            .long_format = long_format,
        };
    }

    /// Create a Command interface from this implementation
    pub fn asCommand(self: *DevicesCommand) Command {
        return Command{
            .vtable = &.{
                .execute = execute,
                .deinit = deinit,
            },
            .context = self,
        };
    }

    /// Execute implementation
    fn execute(ctx: *anyopaque, transport_ptr: *transport.Transport, allocator: std.mem.Allocator) protocol.Error!void {
        const self: *DevicesCommand = @ptrCast(ctx);
        _ = transport_ptr; // Not used for this command
        _ = allocator; // Not used for this command

        try self.device_manager.scanDevices();

        // Print the devices
        const stdout = std.io.getStdOut().writer();

        for (self.device_manager.devices.items) |device_info| {
            try stdout.print("{s}\t{s}", .{ device_info.serial, device_info.state.toString() });

            if (self.long_format) {
                if (device_info.product) |product| {
                    try stdout.print(" product:{s}", .{product});
                }
                if (device_info.model) |model| {
                    try stdout.print(" model:{s}", .{model});
                }
                if (device_info.device) |device_name| {
                    try stdout.print(" device:{s}", .{device_name});
                }

                // Print features
                var feature_it = device_info.features.keyIterator();
                while (feature_it.next()) |feature| {
                    try stdout.print(" features:{s}", .{feature.*});
                }
            }

            try stdout.print("\n", .{});
        }
    }

    /// Deinit implementation
    fn deinit(ctx: *anyopaque) void {
        _ = ctx; // Nothing to clean up for this command
    }
};

/// Shell command - runs a shell command on the device
pub const ShellCommand = struct {
    allocator: std.mem.Allocator,
    command: []const u8,
    device_serial: ?[]const u8,

    /// Initialize a new shell command
    pub fn init(allocator: std.mem.Allocator, command: []const u8, device_serial: ?[]const u8) !ShellCommand {
        return ShellCommand{
            .allocator = allocator,
            .command = try allocator.dupe(u8, command),
            .device_serial = if (device_serial) |s| try allocator.dupe(u8, s) else null,
        };
    }

    /// Deinitialize the shell command
    pub fn deinit(self: *ShellCommand) void {
        self.allocator.free(self.command);
        if (self.device_serial) |s| {
            self.allocator.free(s);
        }
    }

    /// Create a Command interface from this implementation
    pub fn asCommand(self: *ShellCommand) Command {
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
        const self: *ShellCommand = @ptrCast(ctx);

        // Connect to the device
        try transport_ptr.connect(self.device_serial);
        defer transport_ptr.disconnect();

        // TODO: Implement shell command execution
        // This would involve opening a shell stream and sending/receiving data

        // For now, just print a message
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Would execute command: {s}\n", .{self.command});

        _ = allocator; // Not used for now
    }

    /// Deinit wrapper implementation
    fn deinitWrapper(ctx: *anyopaque) void {
        const self: *ShellCommand = @ptrCast(ctx);
        self.deinit();
    }
};

/// Push command - pushes a file to the device
pub const PushCommand = struct {
    allocator: std.mem.Allocator,
    local_path: []const u8,
    remote_path: []const u8,
    device_serial: ?[]const u8,

    /// Initialize a new push command
    pub fn init(allocator: std.mem.Allocator, local_path: []const u8, remote_path: []const u8, device_serial: ?[]const u8) !PushCommand {
        return PushCommand{
            .allocator = allocator,
            .local_path = try allocator.dupe(u8, local_path),
            .remote_path = try allocator.dupe(u8, remote_path),
            .device_serial = if (device_serial) |s| try allocator.dupe(u8, s) else null,
        };
    }

    /// Deinitialize the push command
    pub fn deinit(self: *PushCommand) void {
        self.allocator.free(self.local_path);
        self.allocator.free(self.remote_path);
        if (self.device_serial) |s| {
            self.allocator.free(s);
        }
    }

    /// Create a Command interface from this implementation
    pub fn asCommand(self: *PushCommand) Command {
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
        const self: *PushCommand = @ptrCast(ctx);

        // Connect to the device
        try transport_ptr.connect(self.device_serial);
        defer transport_ptr.disconnect();

        // TODO: Implement file push
        // This would involve opening a sync connection and sending the file data

        // For now, just print a message
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Would push file from {s} to {s}\n", .{ self.local_path, self.remote_path });

        _ = allocator; // Not used for now
    }

    /// Deinit wrapper implementation
    fn deinitWrapper(ctx: *anyopaque) void {
        const self: *PushCommand = @ptrCast(ctx);
        self.deinit();
    }
};
