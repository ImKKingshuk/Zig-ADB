//! This module handles ADB device management and discovery.

const std = @import("std");
const protocol = @import("protocol.zig");
const transport = @import("transport.zig");

/// Device state
pub const DeviceState = enum {
    offline, // Device is not connected
    bootloader, // Device is in bootloader mode
    recovery, // Device is in recovery mode
    device, // Device is connected and ready
    host, // Device is in host mode
    unauthorized, // Device is connected but not authorized

    /// Convert device state to string
    pub fn toString(self: DeviceState) []const u8 {
        return switch (self) {
            .offline => "offline",
            .bootloader => "bootloader",
            .recovery => "recovery",
            .device => "device",
            .host => "host",
            .unauthorized => "unauthorized",
        };
    }

    /// Parse device state from string
    pub fn fromString(str: []const u8) ?DeviceState {
        if (std.mem.eql(u8, str, "offline")) return .offline;
        if (std.mem.eql(u8, str, "bootloader")) return .bootloader;
        if (std.mem.eql(u8, str, "recovery")) return .recovery;
        if (std.mem.eql(u8, str, "device")) return .device;
        if (std.mem.eql(u8, str, "host")) return .host;
        if (std.mem.eql(u8, str, "unauthorized")) return .unauthorized;
        return null;
    }
};

/// Device information
pub const DeviceInfo = struct {
    serial: []const u8,
    state: DeviceState,
    product: ?[]const u8,
    model: ?[]const u8,
    device: ?[]const u8,
    features: std.StringHashMap(void),

    /// Initialize a new device info
    pub fn init(allocator: std.mem.Allocator, serial: []const u8, state: DeviceState) !DeviceInfo {
        return DeviceInfo{
            .serial = try allocator.dupe(u8, serial),
            .state = state,
            .product = null,
            .model = null,
            .device = null,
            .features = std.StringHashMap(void).init(allocator),
        };
    }

    /// Deinitialize device info
    pub fn deinit(self: *DeviceInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.serial);
        if (self.product) |p| allocator.free(p);
        if (self.model) |m| allocator.free(m);
        if (self.device) |d| allocator.free(d);
        self.features.deinit();
    }

    /// Add a feature to the device
    pub fn addFeature(self: *DeviceInfo, feature: []const u8) !void {
        try self.features.put(feature, {});
    }

    /// Check if the device has a feature
    pub fn hasFeature(self: DeviceInfo, feature: []const u8) bool {
        return self.features.contains(feature);
    }
};

/// Device manager
pub const DeviceManager = struct {
    allocator: std.mem.Allocator,
    devices: std.ArrayList(DeviceInfo),

    /// Initialize a new device manager
    pub fn init(allocator: std.mem.Allocator) DeviceManager {
        return DeviceManager{
            .allocator = allocator,
            .devices = std.ArrayList(DeviceInfo).init(allocator),
        };
    }

    /// Deinitialize the device manager
    pub fn deinit(self: *DeviceManager) void {
        for (self.devices.items) |*device_info| {
            device_info.deinit(self.allocator);
        }
        self.devices.deinit();
    }

    /// Scan for devices
    pub fn scanDevices(self: *DeviceManager) !void {
        // Clear existing devices
        for (self.devices.items) |*device_info| {
            device_info.deinit(self.allocator);
        }
        self.devices.clearRetainingCapacity();

        // TODO: Implement actual device scanning
        // This would involve using the transport layer to discover devices

        // For now, just add a dummy device for testing
        var device_info = try DeviceInfo.init(self.allocator, "emulator-5554", .device);
        try device_info.addFeature(protocol.ConnectionString.FEATURE_SHELL_V2);
        try self.devices.append(device_info);
    }

    /// Find a device by serial
    pub fn findDevice(self: DeviceManager, serial: []const u8) ?DeviceInfo {
        for (self.devices.items) |device_info| {
            if (std.mem.eql(u8, device_info.serial, serial)) {
                return device_info;
            }
        }
        return null;
    }

    /// Get the number of devices
    pub fn deviceCount(self: DeviceManager) usize {
        return self.devices.items.len;
    }
};
