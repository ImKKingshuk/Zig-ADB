//! This module implements the logcat command for Zig-ADB.

const std = @import("std");
const protocol = @import("../protocol.zig");
const device = @import("../device.zig");
const transport = @import("../transport.zig");
const Command = @import("../commands.zig").Command;

/// Logcat command - streams device logs
pub const LogcatCommand = struct {
    allocator: std.mem.Allocator,
    device_serial: ?[]const u8,
    options: LogcatOptions,

    /// Logcat options
    pub const LogcatOptions = struct {
        clear: bool = false,
        dump: bool = false,
        format: Format = .brief,
        buffer: ?[]const u8 = null,
        filters: std.ArrayList([]const u8),

        /// Format options for logcat output
        pub const Format = enum {
            brief,
            process,
            tag,
            thread,
            raw,
            time,
            threadtime,
            long,
        };

        /// Initialize logcat options
        pub fn init(allocator: std.mem.Allocator) LogcatOptions {
            return LogcatOptions{
                .filters = std.ArrayList([]const u8).init(allocator),
            };
        }

        /// Deinitialize logcat options
        pub fn deinit(self: *LogcatOptions) void {
            for (self.filters.items) |filter| {
                self.filters.allocator.free(filter);
            }
            self.filters.deinit();
            if (self.buffer) |buffer| {
                self.filters.allocator.free(buffer);
            }
        }

        /// Add a filter to logcat options
        pub fn addFilter(self: *LogcatOptions, filter: []const u8) !void {
            const filter_copy = try self.filters.allocator.dupe(u8, filter);
            try self.filters.append(filter_copy);
        }

        /// Set the buffer for logcat options
        pub fn setBuffer(self: *LogcatOptions, buffer: []const u8) !void {
            if (self.buffer) |old_buffer| {
                self.filters.allocator.free(old_buffer);
            }
            self.buffer = try self.filters.allocator.dupe(u8, buffer);
        }

        /// Format to string representation
        pub fn formatToString(format: Format) []const u8 {
            return switch (format) {
                .brief => "brief",
                .process => "process",
                .tag => "tag",
                .thread => "thread",
                .raw => "raw",
                .time => "time",
                .threadtime => "threadtime",
                .long => "long",
            };
        }
    };

    /// Initialize a new logcat command
    pub fn init(allocator: std.mem.Allocator, device_serial: ?[]const u8) !LogcatCommand {
        return LogcatCommand{
            .allocator = allocator,
            .device_serial = if (device_serial) |s| try allocator.dupe(u8, s) else null,
            .options = LogcatOptions.init(allocator),
        };
    }

    /// Deinitialize the logcat command
    pub fn deinit(self: *LogcatCommand) void {
        if (self.device_serial) |s| {
            self.allocator.free(s);
        }
        self.options.deinit();
    }

    /// Create a Command interface from this implementation
    pub fn asCommand(self: *LogcatCommand) Command {
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
        const self: *LogcatCommand = @ptrCast(ctx);

        // Connect to the device
        try transport_ptr.connect(self.device_serial);
        defer transport_ptr.disconnect();

        // Build the logcat command
        var cmd_buffer = std.ArrayList(u8).init(allocator);
        defer cmd_buffer.deinit();

        try cmd_buffer.appendSlice("shell:logcat");

        // Add options
        if (self.options.clear) {
            try cmd_buffer.appendSlice(" -c");
        }

        if (self.options.dump) {
            try cmd_buffer.appendSlice(" -d");
        }

        // Add format
        try cmd_buffer.appendSlice(" -v ");
        try cmd_buffer.appendSlice(LogcatOptions.formatToString(self.options.format));

        // Add buffer if specified
        if (self.options.buffer) |buffer| {
            try cmd_buffer.appendSlice(" -b ");
            try cmd_buffer.appendSlice(buffer);
        }

        // Add filters
        for (self.options.filters.items) |filter| {
            try cmd_buffer.append(' ');
            try cmd_buffer.appendSlice(filter);
        }

        // Send the command
        const header = protocol.MessageHeader.init(.OPEN, 0, 0, cmd_buffer.items.len);
        try transport_ptr.send(header, cmd_buffer.items);

        // Receive and process the response
        const stdout = std.io.getStdOut().writer();
        var running = true;

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
    }

    /// Deinit wrapper implementation
    fn deinitWrapper(ctx: *anyopaque) void {
        const self: *LogcatCommand = @ptrCast(ctx);
        self.deinit();
    }