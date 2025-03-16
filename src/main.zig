//! Main entry point for the Zig-ADB client.

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    var args = parseArgs(allocator) catch |err| {
        std.debug.print("Error parsing arguments: {s}\n", .{@errorName(err)});
        printUsage();
        return;
    };
    defer args.deinit();

    // Execute the command
    executeCommand(allocator, args) catch |err| {
        std.debug.print("Error executing command: {s}\n", .{@errorName(err)});
        return;
    };
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "use other module" {
    const lib = @import("lib.zig");
    try std.testing.expectEqual(@as(i32, 150), lib.add(100, 50));
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

const std = @import("std");
const protocol = @import("protocol.zig");
const device = @import("device.zig");
const transport = @import("transport.zig");
const commands = @import("commands.zig");

/// Print usage information
fn printUsage() void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("Zig-ADB - Android Debug Bridge implementation in Zig\n", .{}) catch {};
    stderr.print("\nUsage: zig-adb [options] <command> [command-arguments]\n", .{}) catch {};
    stderr.print("\nOptions:\n", .{}) catch {};
    stderr.print("  -s <serial>       Use device with the given serial\n", .{}) catch {};
    stderr.print("  -d                Use the first USB device\n", .{}) catch {};
    stderr.print("  -e                Use the first emulator\n", .{}) catch {};
    stderr.print("  -t <transport>    Use the given transport (usb, local, tcp)\n", .{}) catch {};
    stderr.print("  -H <host>         Name of adb server host (default: localhost)\n", .{}) catch {};
    stderr.print("  -P <port>         Port of adb server (default: 5037)\n", .{}) catch {};
    stderr.print("\nCommands:\n", .{}) catch {};
    stderr.print("  devices [-l]      List connected devices (-l for long output)\n", .{}) catch {};
    stderr.print("  shell [<command>] Run remote shell command\n", .{}) catch {};
    stderr.print("  push <local> <remote>\n", .{}) catch {};
    stderr.print("                    Copy file/dir to device\n", .{}) catch {};
    stderr.print("  version           Show version\n", .{}) catch {};
    stderr.print("  help              Show this help message\n", .{}) catch {};
}

/// Print version information
fn printVersion() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("Zig-ADB version 0.1.0\n", .{}) catch {};
    stdout.print("Android Debug Bridge implementation in Zig\n", .{}) catch {};
}

/// Command line arguments
const Args = struct {
    device_serial: ?[]const u8 = null,
    transport_type: transport.TransportType = .usb,
    host: []const u8 = "localhost",
    port: u16 = 5037,
    command: ?[]const u8 = null,
    command_args: std.ArrayList([]const u8),

    fn deinit(self: *Args) void {
        self.command_args.deinit();
    }
};

/// Parse command line arguments
fn parseArgs(allocator: std.mem.Allocator) !Args {
    var args = Args{
        .command_args = std.ArrayList([]const u8).init(allocator),
    };

    var arg_iter = try std.process.argsWithAllocator(allocator);
    defer arg_iter.deinit();

    // Skip program name
    _ = arg_iter.skip();

    // Parse options
    while (arg_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-s")) {
            args.device_serial = arg_iter.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "-t")) {
            const transport_str = arg_iter.next() orelse return error.MissingArgument;
            if (std.mem.eql(u8, transport_str, "usb")) {
                args.transport_type = .usb;
            } else if (std.mem.eql(u8, transport_str, "local")) {
                args.transport_type = .local;
            } else if (std.mem.eql(u8, transport_str, "tcp")) {
                args.transport_type = .tcp;
            } else {
                return error.InvalidTransport;
            }
        } else if (std.mem.eql(u8, arg, "-H")) {
            args.host = arg_iter.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "-P")) {
            const port_str = arg_iter.next() orelse return error.MissingArgument;
            args.port = try std.fmt.parseInt(u16, port_str, 10);
        } else if (std.mem.startsWith(u8, arg, "-")) {
            // Unrecognized option
            return error.InvalidOption;
        } else {
            // Command
            args.command = arg;
            break;
        }
    }

    // Parse command arguments
    while (arg_iter.next()) |arg| {
        try args.command_args.append(arg);
    }

    return args;
}

/// Execute a command
fn executeCommand(allocator: std.mem.Allocator, args: Args) !void {
    var device_manager = device.DeviceManager.init(allocator);
    defer device_manager.deinit();

    var usb_transport = transport.UsbTransport.init(allocator);
    defer usb_transport.deinit();

    var transport_ptr = usb_transport.asTransport();

    if (args.command) |cmd| {
        if (std.mem.eql(u8, cmd, "devices")) {
            // Check for -l option
            const long_format = if (args.command_args.items.len > 0 and
                std.mem.eql(u8, args.command_args.items[0], "-l")) true else false;

            var devices_cmd = commands.DevicesCommand.init(allocator, &device_manager, long_format);
            var command = devices_cmd.asCommand();
            try command.execute(&transport_ptr, allocator);
        } else if (std.mem.eql(u8, cmd, "shell")) {
            if (args.command_args.items.len == 0) {
                // Interactive shell not implemented yet
                std.debug.print("Interactive shell not implemented yet\n", .{});
                return;
            }

            // Join all arguments with spaces
            var shell_cmd = std.ArrayList(u8).init(allocator);
            defer shell_cmd.deinit();

            for (args.command_args.items, 0..) |arg, i| {
                try shell_cmd.appendSlice(arg);
                if (i < args.command_args.items.len - 1) {
                    try shell_cmd.append(' ');
                }
            }

            var shell_command = try commands.ShellCommand.init(allocator, shell_cmd.items, args.device_serial);
            defer shell_command.deinit();

            var command = shell_command.asCommand();
            try command.execute(&transport_ptr, allocator);
        } else if (std.mem.eql(u8, cmd, "push")) {
            if (args.command_args.items.len < 2) {
                std.debug.print("push requires local and remote path arguments\n", .{});
                return error.InvalidArguments;
            }

            var push_command = try commands.PushCommand.init(allocator, args.command_args.items[0], args.command_args.items[1], args.device_serial);
            defer push_command.deinit();

            var command = push_command.asCommand();
            try command.execute(&transport_ptr, allocator);
        } else if (std.mem.eql(u8, cmd, "version")) {
            printVersion();
        } else if (std.mem.eql(u8, cmd, "help")) {
            printUsage();
        } else {
            std.debug.print("Unknown command: {s}\n", .{cmd});
            printUsage();
        }
    } else {
        // No command specified
        printUsage();
    }
}
