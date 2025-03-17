//! This module implements the install command for Zig-ADB.

const std = @import("std");
const protocol = @import("../protocol.zig");
const device = @import("../device.zig");
const transport = @import("../transport.zig");
const Command = @import("../commands.zig").Command;

/// Install command - installs an APK on the device
pub const InstallCommand = struct {
    allocator: std.mem.Allocator,
    apk_path: []const u8,
    device_serial: ?[]const u8,
    options: InstallOptions,

    /// Install options
    pub const InstallOptions = struct {
        replace_existing: bool = false,
        allow_test_packages: bool = false,
        allow_downgrade: bool = false,
        grant_permissions: bool = false,
        install_location: ?InstallLocation = null,

        /// Install location options
        pub const InstallLocation = enum {
            auto,
            internal,
            external,
        };

        /// Initialize install options
        pub fn init() InstallOptions {
            return InstallOptions{};
        }

        /// Convert install location to string
        pub fn locationToString(location: InstallLocation) []const u8 {
            return switch (location) {
                .auto => "0",
                .internal => "1",
                .external => "2",
            };
        }
    };

    /// Initialize a new install command
    pub fn init(allocator: std.mem.Allocator, apk_path: []const u8, device_serial: ?[]const u8) !InstallCommand {
        return InstallCommand{
            .allocator = allocator,
            .apk_path = try allocator.dupe(u8, apk_path),
            .device_serial = if (device_serial) |s| try allocator.dupe(u8, s) else null,
            .options = InstallOptions.init(),
        };
    }

    /// Deinitialize the install command
    pub fn deinit(self: *InstallCommand) void {
        self.allocator.free(self.apk_path);
        if (self.device_serial) |s| {
            self.allocator.free(s);
        }
    }

    /// Create a Command interface from this implementation
    pub fn asCommand(self: *InstallCommand) Command {
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
        const self: *InstallCommand = @ptrCast(ctx);

        // Connect to the device
        try transport_ptr.connect(self.device_serial);
        defer transport_ptr.disconnect();

        // Build the install command
        var cmd_buffer = std.ArrayList(u8).init(allocator);
        defer cmd_buffer.deinit();

        try cmd_buffer.appendSlice("shell:pm install");

        // Add options
        if (self.options.replace_existing) {
            try cmd_buffer.appendSlice(" -r");
        }

        if (self.options.allow_test_packages) {
            try cmd_buffer.appendSlice(" -t");
        }

        if (self.options.allow_downgrade) {
            try cmd_buffer.appendSlice(" -d");
        }

        if (self.options.grant_permissions) {
            try cmd_buffer.appendSlice(" -g");
        }

        if (self.options.install_location) |location| {
            try cmd_buffer.appendSlice(" -l ");
            try cmd_buffer.appendSlice(InstallOptions.locationToString(location));
        }

        // First, we need to push the APK to a temporary location on the device
        const temp_path = "/data/local/tmp/temp.apk";
        try pushApkToDevice(self, transport_ptr, allocator, temp_path);

        // Add the path to the command
        try cmd_buffer.append(' ');
        try cmd_buffer.appendSlice(temp_path);

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

        // Clean up the temporary APK
        try cleanupTempApk(self, transport_ptr, allocator, temp_path);

        if (!success) {
            return protocol.Error.CommandFailed;
        }

        try stdout.print("Successfully installed {s}\n", .{self.apk_path});
    }

    /// Push the APK to a temporary location on the device
    fn pushApkToDevice(self: *InstallCommand, transport_ptr: *transport.Transport, allocator: std.mem.Allocator, temp_path: []const u8) !void {
        // Build the sync command
        var cmd_buffer = std.ArrayList(u8).init(allocator);
        defer cmd_buffer.deinit();

        try cmd_buffer.appendSlice("sync:");

        // Send the sync command
        const header = protocol.MessageHeader.init(.OPEN, 0, 0, cmd_buffer.items.len);
        try transport_ptr.send(header, cmd_buffer.items);

        // Receive the response
        const response = try transport_ptr.receive(allocator);
        defer if (response.data) |data| allocator.free(data);

        if (response.header.command != .OKAY) {
            return protocol.Error.CommandFailed;
        }

        // Send the SEND command
        const send_cmd = "SEND";
        const send_header = protocol.MessageHeader.init(.WRTE, 0, 0, send_cmd.len);
        try transport_ptr.send(send_header, send_cmd);

        // Send the path and mode
        var path_with_mode = std.ArrayList(u8).init(allocator);
        defer path_with_mode.deinit();

        try path_with_mode.appendSlice(temp_path);
        try path_with_mode.appendSlice(",0644");

        // Send the path length
        const path_len = @intCast(u32, path_with_mode.items.len);
        const path_len_bytes = std.mem.asBytes(&path_len);
        const path_len_header = protocol.MessageHeader.init(.WRTE, 0, 0, path_len_bytes.len);
        try transport_ptr.send(path_len_header, path_len_bytes);

        // Send the path with mode
        const path_header = protocol.MessageHeader.init(.WRTE, 0, 0, path_with_mode.items.len);
        try transport_ptr.send(path_header, path_with_mode.items);

        // Open the APK file
        const file = try std.fs.cwd().openFile(self.apk_path, .{});
        defer file.close();

        // Get file size
        const file_size = try file.getEndPos();

        // Read and send the file in chunks
        var buffer: [8192]u8 = undefined;
        var bytes_read: usize = 0;

        while (bytes_read < file_size) {
            const read_size = try file.read(&buffer);
            if (read_size == 0) break;

            const data_header = protocol.MessageHeader.init(.WRTE, 0, 0, read_size);
            try transport_ptr.send(data_header, buffer[0..read_size]);

            bytes_read += read_size;
        }

        // Send DONE command with timestamp
        const timestamp = @intCast(u32, std.time.timestamp());
        const timestamp_bytes = std.mem.asBytes(&timestamp);

        const done_cmd = "DONE";
        const done_header = protocol.MessageHeader.init(.WRTE, 0, 0, done_cmd.len + timestamp_bytes.len);

        var done_buffer = std.ArrayList(u8).init(allocator);
        defer done_buffer.deinit();

        try done_buffer.appendSlice(done_cmd);
        try done_buffer.appendSlice(timestamp_bytes);

        try transport_ptr.send(done_header, done_buffer.items);

        // Wait for OKAY response
        const done_response = try transport_ptr.receive(allocator);
        defer if (done_response.data) |data| allocator.free(data);

        if (done_response.header.command != .OKAY) {
            return protocol.Error.CommandFailed;
        }

        // Close the sync connection
        const close_header = protocol.MessageHeader.init(.CLSE, 0, 0, 0);
        try transport_ptr.send(close_header, null);
    }

    /// Clean up the temporary APK file
    fn cleanupTempApk(self: *InstallCommand, transport_ptr: *transport.Transport, allocator: std.mem.Allocator, temp_path: []const u8) !void {
        _ = self; // Unused

        // Build the cleanup command
        var cmd_buffer = std.ArrayList(u8).init(allocator);
        defer cmd_buffer.deinit();

        try cmd_buffer.appendSlice("shell:rm ");
        try cmd_buffer.appendSlice(temp_path);

        // Send the command
        const header = protocol.MessageHeader.init(.OPEN, 0, 0, cmd_buffer.items.len);
        try transport_ptr.send(header, cmd_buffer.items);

        // Receive the response and ignore the result
        const response = try transport_ptr.receive(allocator);
        defer if (response.data) |data| allocator.free(data);

        // Close the connection
        const close_header = protocol.MessageHeader.init(.CLSE, 0, 0, 0);
        try transport_ptr.send(close_header, null);
    }

    /// Deinit wrapper implementation
    fn deinitWrapper(ctx: *anyopaque) void {
        const self: *InstallCommand = @ptrCast(ctx);
        self.deinit();
    }
};
