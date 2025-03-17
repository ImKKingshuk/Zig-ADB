//! This module implements the pull command for Zig-ADB.

const std = @import("std");
const protocol = @import("../protocol.zig");
const device = @import("../device.zig");
const transport = @import("../transport.zig");
const Command = @import("../commands.zig").Command;

/// Pull command - pulls a file from the device
pub const PullCommand = struct {
    allocator: std.mem.Allocator,
    remote_path: []const u8,
    local_path: []const u8,
    device_serial: ?[]const u8,

    /// Initialize a new pull command
    pub fn init(allocator: std.mem.Allocator, remote_path: []const u8, local_path: []const u8, device_serial: ?[]const u8) !PullCommand {
        return PullCommand{
            .allocator = allocator,
            .remote_path = try allocator.dupe(u8, remote_path),
            .local_path = try allocator.dupe(u8, local_path),
            .device_serial = if (device_serial) |s| try allocator.dupe(u8, s) else null,
        };
    }

    /// Deinitialize the pull command
    pub fn deinit(self: *PullCommand) void {
        self.allocator.free(self.remote_path);
        self.allocator.free(self.local_path);
        if (self.device_serial) |s| {
            self.allocator.free(s);
        }
    }

    /// Create a Command interface from this implementation
    pub fn asCommand(self: *PullCommand) Command {
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
        const self: *PullCommand = @ptrCast(ctx);

        // Connect to the device
        try transport_ptr.connect(self.device_serial);
        defer transport_ptr.disconnect();

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

        // Send the RECV command
        const recv_cmd = "RECV";
        const recv_header = protocol.MessageHeader.init(.WRTE, 0, 0, recv_cmd.len);
        try transport_ptr.send(recv_header, recv_cmd);

        // Send the path length
        const path_len = @intCast(u32, self.remote_path.len);
        const path_len_bytes = std.mem.asBytes(&path_len);
        const path_len_header = protocol.MessageHeader.init(.WRTE, 0, 0, path_len_bytes.len);
        try transport_ptr.send(path_len_header, path_len_bytes);

        // Send the path
        const path_header = protocol.MessageHeader.init(.WRTE, 0, 0, self.remote_path.len);
        try transport_ptr.send(path_header, self.remote_path);

        // Create the local file
        const file = try std.fs.cwd().createFile(self.local_path, .{});
        defer file.close();

        // Receive and write the file data
        var running = true;
        while (running) {
            const data_response = try transport_ptr.receive(allocator);
            defer if (data_response.data) |data| allocator.free(data);

            switch (data_response.header.command) {
                .WRTE => {
                    if (data_response.data) |data| {
                        // Check for DONE or FAIL
                        if (data.len >= 4 and std.mem.eql(u8, data[0..4], "DONE")) {
                            running = false;
                        } else if (data.len >= 4 and std.mem.eql(u8, data[0..4], "FAIL")) {
                            return protocol.Error.CommandFailed;
                        } else {
                            // Write the data to the file
                            try file.writeAll(data);
                        }
                    }
                },
                .CLSE => {
                    running = false;
                },
                else => {
                    return protocol.Error.InvalidResponse;
                },
            }
        }

        // Print success message
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Pulled {s} to {s}\n", .{ self.remote_path, self.local_path });
    }

    /// Deinit wrapper implementation
    fn deinitWrapper(ctx: *anyopaque) void {
        const self: *PullCommand = @ptrCast(ctx);
        self.deinit();
    }
};
