//! This module handles transport mechanisms for ADB communication.

const std = @import("std");
const protocol = @import("protocol.zig");

/// Transport type
pub const TransportType = enum {
    usb, // USB connection
    local, // Local connection (ADB server)
    tcp, // TCP/IP connection

    /// Convert transport type to string
    pub fn toString(self: TransportType) []const u8 {
        return switch (self) {
            .usb => "usb",
            .local => "local",
            .tcp => "tcp",
        };
    }
};

/// Transport interface
pub const Transport = struct {
    vtable: *const VTable,
    context: *anyopaque,

    pub const VTable = struct {
        connect: *const fn (ctx: *anyopaque, serial: ?[]const u8) protocol.Error!void,
        disconnect: *const fn (ctx: *anyopaque) void,
        send: *const fn (ctx: *anyopaque, header: protocol.MessageHeader, data: ?[]const u8) protocol.Error!void,
        receive: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) protocol.Error!struct { header: protocol.MessageHeader, data: ?[]u8 },
    };

    /// Connect to a device
    pub fn connect(self: *Transport, serial: ?[]const u8) protocol.Error!void {
        return self.vtable.connect(self.context, serial);
    }

    /// Disconnect from a device
    pub fn disconnect(self: *Transport) void {
        self.vtable.disconnect(self.context);
    }

    /// Send a message
    pub fn send(self: *Transport, header: protocol.MessageHeader, data: ?[]const u8) protocol.Error!void {
        return self.vtable.send(self.context, header, data);
    }

    /// Receive a message
    pub fn receive(self: *Transport, allocator: std.mem.Allocator) protocol.Error!struct { header: protocol.MessageHeader, data: ?[]u8 } {
        return self.vtable.receive(self.context, allocator);
    }
};

/// USB Transport implementation
pub const UsbTransport = struct {
    allocator: std.mem.Allocator,
    connected: bool,
    device_serial: ?[]const u8,

    /// Initialize a new USB transport
    pub fn init(allocator: std.mem.Allocator) UsbTransport {
        return UsbTransport{
            .allocator = allocator,
            .connected = false,
            .device_serial = null,
        };
    }

    /// Deinitialize the USB transport
    pub fn deinit(self: *UsbTransport) void {
        if (self.device_serial) |serial| {
            self.allocator.free(serial);
            self.device_serial = null;
        }
    }

    /// Create a Transport interface from this implementation
    pub fn asTransport(self: *UsbTransport) Transport {
        return Transport{
            .vtable = &.{
                .connect = connect,
                .disconnect = disconnect,
                .send = send,
                .receive = receive,
            },
            .context = self,
        };
    }

    /// Connect implementation
    fn connect(ctx: *anyopaque, serial: ?[]const u8) protocol.Error!void {
        const self: *UsbTransport = @ptrCast(ctx);

        // TODO: Implement actual USB device connection
        // This would involve finding the USB device with the given serial
        // and establishing a connection to it

        if (serial) |s| {
            self.device_serial = self.allocator.dupe(u8, s) catch return protocol.Error.ConnectionFailed;
        }

        self.connected = true;
        return;
    }

    /// Disconnect implementation
    fn disconnect(ctx: *anyopaque) void {
        const self: *UsbTransport = @ptrCast(ctx);

        if (self.device_serial) |serial| {
            self.allocator.free(serial);
            self.device_serial = null;
        }

        self.connected = false;
    }

    /// Send implementation
    fn send(ctx: *anyopaque) protocol.Error!void {
        const self: *UsbTransport = @ptrCast(ctx);

        if (!self.connected) {
            return protocol.Error.ConnectionFailed;
        }

        // TODO: Implement actual USB data sending
        // This would involve sending the header and data over the USB connection

        return;
    }

    /// Receive implementation
    fn receive(ctx: *anyopaque) protocol.Error!struct { header: protocol.MessageHeader, data: ?[]u8 } {
        const self: *UsbTransport = @ptrCast(ctx);

        if (!self.connected) {
            return protocol.Error.ConnectionFailed;
        }

        // TODO: Implement actual USB data receiving
        // This would involve receiving the header and data from the USB connection

        // For now, return a dummy response
        return .{
            .header = protocol.MessageHeader.init(.CNXN, 0, 0, 0),
            .data = null,
        };
    }
};

/// TCP Transport implementation
pub const TcpTransport = struct {
    allocator: std.mem.Allocator,
    connected: bool,
    stream: ?std.net.Stream,
    host: []const u8,
    port: u16,

    /// Initialize a new TCP transport
    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !TcpTransport {
        return TcpTransport{
            .allocator = allocator,
            .connected = false,
            .stream = null,
            .host = try allocator.dupe(u8, host),
            .port = port,
        };
    }

    /// Deinitialize the TCP transport
    pub fn deinit(self: *TcpTransport) void {
        if (self.stream) |stream| {
            stream.close();
        }
        self.allocator.free(self.host);
    }

    /// Create a Transport interface from this implementation
    pub fn asTransport(self: *TcpTransport) Transport {
        return Transport{
            .vtable = &.{
                .connect = connect,
                .disconnect = disconnect,
                .send = send,
                .receive = receive,
            },
            .context = self,
        };
    }

    /// Connect implementation
    fn connect(ctx: *anyopaque, serial: ?[]const u8) protocol.Error!void {
        const self: *TcpTransport = @ptrCast(ctx);

        if (self.connected) {
            return protocol.Error.ConnectionFailed; // Already connected
        }

        // Establish TCP connection
        const address = std.net.Address.parseIp(self.host, self.port) catch return protocol.Error.ConnectionFailed;
        self.stream = std.net.tcpConnectToAddress(address) catch return protocol.Error.ConnectionFailed;
        self.connected = true;

        _ = serial; // Unused in TCP, but included for interface compatibility
        return;
    }

    /// Disconnect implementation
    fn disconnect(ctx: *anyopaque) void {
        const self: *TcpTransport = @ptrCast(ctx);

        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }
        self.connected = false;
    }

    /// Send implementation
    fn send(ctx: *anyopaque, header: protocol.MessageHeader, data: ?[]const u8) protocol.Error!void {
        const self: *TcpTransport = @ptrCast(ctx);

        if (!self.connected or self.stream == null) {
            return protocol.Error.ConnectionFailed;
        }

        const stream = self.stream.?;
        // TODO: Implement actual TCP data sending
        // For now, this is a placeholder
        _ = try stream.write(std.mem.asBytes(&header));
        if (data) |d| {
            _ = try stream.write(d);
        }
    }

    /// Receive implementation
    fn receive(ctx: *anyopaque) protocol.Error!struct { header: protocol.MessageHeader, data: ?[]u8 } {
        const self: *TcpTransport = @ptrCast(ctx);

        if (!self.connected or self.stream == null) {
            return protocol.Error.ConnectionFailed;
        }

        _ = self.stream.?;
        // TODO: Implement actual TCP data receiving
        // For now, return a dummy response
        return .{
            .header = protocol.MessageHeader.init(.CNXN, 0, 0, 0),
            .data = null,
        };
    }
};
