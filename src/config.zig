//! This module handles configuration and user preferences for Zig-ADB.

const std = @import("std");

/// Configuration structure
pub const Config = struct {
    allocator: std.mem.Allocator,
    config_path: []const u8,
    default_device: ?[]const u8,
    default_transport: ?[]const u8,
    server_host: []const u8,
    server_port: u16,
    connection_timeout_ms: u32,
    wireless_devices: std.StringHashMap([]const u8),

    /// Load configuration from file
    pub fn load(self: *Config) !void {
        // Try to open the config file
        const file = std.fs.openFileAbsolute(self.config_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Config file doesn't exist yet, use defaults
                return;
            }
            return err;
        };
        defer file.close();

        // Read the file content
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        // Parse the content as JSON
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(content);
        defer tree.deinit();

        const root = tree.root;

        // Extract values
        if (root.Object.get("default_device")) |value| {
            if (value != .Null) {
                if (self.default_device) |device| {
                    self.allocator.free(device);
                }
                self.default_device = try self.allocator.dupe(u8, value.String);
            }
        }

        if (root.Object.get("default_transport")) |value| {
            if (value != .Null) {
                if (self.default_transport) |transport| {
                    self.allocator.free(transport);
                }
                self.default_transport = try self.allocator.dupe(u8, value.String);
            }
        }

        if (root.Object.get("server_host")) |value| {
            if (value != .Null) {
                self.allocator.free(self.server_host);
                self.server_host = try self.allocator.dupe(u8, value.String);
            }
        }

        if (root.Object.get("server_port")) |value| {
            if (value != .Null) {
                self.server_port = @intCast(u16, value.Integer);
            }
        }

        if (root.Object.get("connection_timeout_ms")) |value| {
            if (value != .Null) {
                self.connection_timeout_ms = @intCast(u32, value.Integer);
            }
        }

        // Load wireless devices
        if (root.Object.get("wireless_devices")) |value| {
            if (value != .Null and value == .Object) {
                var it = value.Object.iterator();
                while (it.next()) |entry| {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    const val = try self.allocator.dupe(u8, entry.value_ptr.*.String);
                    try self.wireless_devices.put(key, val);
                }
            }
        }
    }

    /// Save configuration to file
    pub fn save(self: *Config) !void {
        // Create a JSON object
        var json = std.json.Value{ .Object = std.json.ObjectMap.init(self.allocator) };
        defer json.Object.deinit();

        // Add values
        try json.Object.put("server_host", std.json.Value{ .String = self.server_host });
        try json.Object.put("server_port", std.json.Value{ .Integer = self.server_port });
        try json.Object.put("connection_timeout_ms", std.json.Value{ .Integer = self.connection_timeout_ms });

        if (self.default_device) |device| {
            try json.Object.put("default_device", std.json.Value{ .String = device });
        } else {
            try json.Object.put("default_device", std.json.Value{ .Null = {} });
        }

        if (self.default_transport) |transport| {
            try json.Object.put("default_transport", std.json.Value{ .String = transport });
        } else {
            try json.Object.put("default_transport", std.json.Value{ .Null = {} });
        }

        // Add wireless devices
        var wireless_json = std.json.Value{ .Object = std.json.ObjectMap.init(self.allocator) };
        var it = self.wireless_devices.iterator();
        while (it.next()) |entry| {
            try wireless_json.Object.put(entry.key_ptr.*, std.json.Value{ .String = entry.value_ptr.* });
        }
        try json.Object.put("wireless_devices", wireless_json);

        // Stringify the JSON
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();

        try std.json.stringify(json, .{}, buf.writer());

        // Write to file
        const file = try std.fs.createFileAbsolute(self.config_path, .{});
        defer file.close();

        try file.writeAll(buf.items);
    }

    /// Set default device
    pub fn setDefaultDevice(self: *Config, device: ?[]const u8) !void {
        if (self.default_device) |old_device| {
            self.allocator.free(old_device);
        }

        self.default_device = if (device) |d| try self.allocator.dupe(u8, d) else null;
        try self.save();
    }

    /// Add a wireless device
    pub fn addWirelessDevice(self: *Config, name: []const u8, address: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        const address_copy = try self.allocator.dupe(u8, address);

        // Remove existing entry if any
        if (self.wireless_devices.get(name_copy)) |old_address| {
            self.allocator.free(old_address);
        }

        try self.wireless_devices.put(name_copy, address_copy);
        try self.save();
    }

    /// Remove a wireless device
    pub fn removeWirelessDevice(self: *Config, name: []const u8) !void {
        if (self.wireless_devices.get(name)) |address| {
            const key = self.wireless_devices.getKey(name) orelse return;
            self.allocator.free(key);
            self.allocator.free(address);
            _ = self.wireless_devices.remove(name);
            try self.save();
        }
    }

    /// Get a wireless device address
    pub fn getWirelessDevice(self: Config, name: []const u8) ?[]const u8 {
        return self.wireless_devices.get(name);
    } Initialize a new configuration
    pub fn init(allocator: std.mem.Allocator) !Config {
        // Get the user's home directory
        const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch "";
        defer allocator.free(home_dir);

        // Create the config path
        const config_path = try std.fs.path.join(allocator, &[_][]const u8{ home_dir, ".zig-adb-config" });

        return Config{
            .allocator = allocator,
            .config_path = config_path,
            .default_device = null,
            .default_transport = null,
            .server_host = try allocator.dupe(u8, "localhost"),
            .server_port = 5037,
            .connection_timeout_ms = 5000,
            .wireless_devices = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Load configuration from file
    pub fn load(self: *Config) !void {
        // Try to open the config file
        const file = std.fs.openFileAbsolute(self.config_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Config file doesn't exist yet, use defaults
                return;
            }
            return err;
        };
        defer file.close();

        // Read the file content
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        // Parse the content as JSON
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(content);
        defer tree.deinit();

        const root = tree.root;

        // Extract values
        if (root.Object.get("default_device")) |value| {
            if (value != .Null) {
                if (self.default_device) |device| {
                    self.allocator.free(device);
                }
                self.default_device = try self.allocator.dupe(u8, value.String);
            }
        }

        if (root.Object.get("default_transport")) |value| {
            if (value != .Null) {
                if (self.default_transport) |transport| {
                    self.allocator.free(transport);
                }
                self.default_transport = try self.allocator.dupe(u8, value.String);
            }
        }

        if (root.Object.get("server_host")) |value| {
            if (value != .Null) {
                self.allocator.free(self.server_host);
                self.server_host = try self.allocator.dupe(u8, value.String);
            }
        }

        if (root.Object.get("server_port")) |value| {
            if (value != .Null) {
                self.server_port = @intCast(u16, value.Integer);
            }
        }

        if (root.Object.get("connection_timeout_ms")) |value| {
            if (value != .Null) {
                self.connection_timeout_ms = @intCast(u32, value.Integer);
            }
        }

        // Load wireless devices
        if (root.Object.get("wireless_devices")) |value| {
            if (value != .Null and value == .Object) {
                var it = value.Object.iterator();
                while (it.next()) |entry| {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    const val = try self.allocator.dupe(u8, entry.value_ptr.*.String);
                    try self.wireless_devices.put(key, val);
                }
            }
        }
    }

    /// Save configuration to file
    pub fn save(self: *Config) !void {
        // Create a JSON object
        var json = std.json.Value{ .Object = std.json.ObjectMap.init(self.allocator) };
        defer json.Object.deinit();

        // Add values
        try json.Object.put("server_host", std.json.Value{ .String = self.server_host });
        try json.Object.put("server_port", std.json.Value{ .Integer = self.server_port });
        try json.Object.put("connection_timeout_ms", std.json.Value{ .Integer = self.connection_timeout_ms });

        if (self.default_device) |device| {
            try json.Object.put("default_device", std.json.Value{ .String = device });
        } else {
            try json.Object.put("default_device", std.json.Value{ .Null = {} });
        }

        if (self.default_transport) |transport| {
            try json.Object.put("default_transport", std.json.Value{ .String = transport });
        } else {
            try json.Object.put("default_transport", std.json.Value{ .Null = {} });
        }

        // Add wireless devices
        var wireless_json = std.json.Value{ .Object = std.json.ObjectMap.init(self.allocator) };
        var it = self.wireless_devices.iterator();
        while (it.next()) |entry| {
            try wireless_json.Object.put(entry.key_ptr.*, std.json.Value{ .String = entry.value_ptr.* });
        }
        try json.Object.put("wireless_devices", wireless_json);

        // Stringify the JSON
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();

        try std.json.stringify(json, .{}, buf.writer());

        // Write to file
        const file = try std.fs.createFileAbsolute(self.config_path, .{});
        defer file.close();

        try file.writeAll(buf.items);
    }

    /// Set default device
    pub fn setDefaultDevice(self: *Config, device: ?[]const u8) !void {
        if (self.default_device) |old_device| {
            self.allocator.free(old_device);
        }

        self.default_device = if (device) |d| try self.allocator.dupe(u8, d) else null;
        try self.save();
    }

    /// Add a wireless device
    pub fn addWirelessDevice(self: *Config, name: []const u8, address: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        const address_copy = try self.allocator.dupe(u8, address);

        // Remove existing entry if any
        if (self.wireless_devices.get(name_copy)) |old_address| {
            self.allocator.free(old_address);
        }

        try self.wireless_devices.put(name_copy, address_copy);
        try self.save();
    }

    /// Remove a wireless device
    pub fn removeWirelessDevice(self: *Config, name: []const u8) !void {
        if (self.wireless_devices.get(name)) |address| {
            const key = self.wireless_devices.getKey(name) orelse return;
            self.allocator.free(key);
            self.allocator.free(address);
            _ = self.wireless_devices.remove(name);
            try self.save();
        }
    }

    /// Get a wireless device address
    pub fn getWirelessDevice(self: Config, name: []const u8) ?[]const u8 {
        return self.wireless_devices.get(name);
    } Deinitialize the configuration
    pub fn deinit(self: *Config) void {
        self.allocator.free(self.config_path);
        if (self.default_device) |device| {
            self.allocator.free(device);
        }
        if (self.default_transport) |transport| {
            self.allocator.free(transport);
        }
        self.allocator.free(self.server_host);

        var it = self.wireless_devices.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.wireless_devices.deinit();
    }

    /// Load configuration from file
    pub fn load(self: *Config) !void {
        // Try to open the config file
        const file = std.fs.openFileAbsolute(self.config_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Config file doesn't exist yet, use defaults
                return;
            }
            return err;
        };
        defer file.close();

        // Read the file content
        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        // Parse the content as JSON
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(content);
        defer tree.deinit();

        const root = tree.root;

        // Extract values
        if (root.Object.get("default_device")) |value| {
            if (value != .Null) {
                if (self.default_device) |device| {
                    self.allocator.free(device);
                }
                self.default_device = try self.allocator.dupe(u8, value.String);
            }
        }

        if (root.Object.get("default_transport")) |value| {
            if (value != .Null) {
                if (self.default_transport) |transport| {
                    self.allocator.free(transport);
                }
                self.default_transport = try self.allocator.dupe(u8, value.String);
            }
        }

        if (root.Object.get("server_host")) |value| {
            if (value != .Null) {
                self.allocator.free(self.server_host);
                self.server_host = try self.allocator.dupe(u8, value.String);
            }
        }

        if (root.Object.get("server_port")) |value| {
            if (value != .Null) {
                self.server_port = @intCast(u16, value.Integer);
            }
        }

        if (root.Object.get("connection_timeout_ms")) |value| {
            if (value != .Null) {
                self.connection_timeout_ms = @intCast(u32, value.Integer);
            }
        }

        // Load wireless devices
        if (root.Object.get("wireless_devices")) |value| {
            if (value != .Null and value == .Object) {
                var it = value.Object.iterator();
                while (it.next()) |entry| {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    const val = try self.allocator.dupe(u8, entry.value_ptr.*.String);
                    try self.wireless_devices.put(key, val);
                }
            }
        }
    }

    /// Save configuration to file
    pub fn save(self: *Config) !void {
        // Create a JSON object
        var json = std.json.Value{ .Object = std.json.ObjectMap.init(self.allocator) };
        defer json.Object.deinit();

        // Add values
        try json.Object.put("server_host", std.json.Value{ .String = self.server_host });
        try json.Object.put("server_port", std.json.Value{ .Integer = self.server_port });
        try json.Object.put("connection_timeout_ms", std.json.Value{ .Integer = self.connection_timeout_ms });

        if (self.default_device) |device| {
            try json.Object.put("default_device", std.json.Value{ .String = device });
        } else {
            try json.Object.put("default_device", std.json.Value{ .Null = {} });
        }

        if (self.default_transport) |transport| {
            try json.Object.put("default_transport", std.json.Value{ .String = transport });
        } else {
            try json.Object.put("default_transport", std.json.Value{ .Null = {} });
        }

        // Add wireless devices
        var wireless_json = std.json.Value{ .Object = std.json.ObjectMap.init(self.allocator) };
        var it = self.wireless_devices.iterator();
        while (it.next()) |entry| {
            try wireless_json.Object.put(entry.key_ptr.*, std.json.Value{ .String = entry.value_ptr.* });
        }
        try json.Object.put("wireless_devices", wireless_json);

        // Stringify the JSON
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();

        try std.json.stringify(json, .{}, buf.writer());

        // Write to file
        const file = try std.fs.createFileAbsolute(self.config_path, .{});
        defer file.close();

        try file.writeAll(buf.items);
    }

    /// Set default device
    pub fn setDefaultDevice(self: *Config, device: ?[]const u8) !void {
        if (self.default_device) |old_device| {
            self.allocator.free(old_device);
        }

        self.default_device = if (device) |d| try self.allocator.dupe(u8, d) else null;
        try self.save();
    }

    /// Add a wireless device
    pub fn addWirelessDevice(self: *Config, name: []const u8, address: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        const address_copy = try self.allocator.dupe(u8, address);

        // Remove existing entry if any
        if (self.wireless_devices.get(name_copy)) |old_address| {
            self.allocator.free(old_address);
        }

        try self.wireless_devices.put(name_copy, address_copy);
        try self.save();
    }

    /// Remove a wireless device
    pub fn removeWirelessDevice(self: *Config, name: []const u8) !void {
        if (self.wireless_devices.get(name)) |address| {
            const key = self.wireless_devices.getKey(name) orelse return;
            self.allocator.free(key);
            self.allocator.free(address);
            _ = self.wireless_devices.remove(name);
            try self.save();
        }
    }

    /// Get a wireless device address
    pub fn getWirelessDevice(self: Config, name: []const u8) ?[]const u8 {
        return self.wireless_devices.get(name);
    }