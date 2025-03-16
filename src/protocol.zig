//! This module defines the ADB protocol specifications and message formats.

const std = @import("std");

/// ADB protocol version
pub const ADB_VERSION = 0x01000000;

/// ADB protocol constants
pub const ADB_PROTOCOL = struct {
    pub const DEFAULT_MAX_DATA = 4096;
    pub const CONNECT_TIMEOUT_MS = 5000;
    pub const DEFAULT_PORT = 5555;
};

/// ADB message command types
pub const CommandType = enum(u32) {
    SYNC = 0x434e5953, // 'SYNC'
    CNXN = 0x4e584e43, // 'CNXN'
    AUTH = 0x48545541, // 'AUTH'
    OPEN = 0x4e45504f, // 'OPEN'
    OKAY = 0x59414b4f, // 'OKAY'
    CLSE = 0x45534c43, // 'CLSE'
    WRTE = 0x45545257, // 'WRTE'
    STLS = 0x534c5453, // 'STLS'
    _,

    /// Convert command type to string
    pub fn toString(self: CommandType) []const u8 {
        return switch (self) {
            .SYNC => "SYNC",
            .CNXN => "CNXN",
            .AUTH => "AUTH",
            .OPEN => "OPEN",
            .OKAY => "OKAY",
            .CLSE => "CLSE",
            .WRTE => "WRTE",
            .STLS => "STLS",
            else => "UNKNOWN",
        };
    }
};

/// ADB authentication types
pub const AuthType = enum(u32) {
    TOKEN = 1,
    SIGNATURE = 2,
    RSAPUBLICKEY = 3,
};

/// ADB message header
pub const MessageHeader = struct {
    command: CommandType,
    arg0: u32,
    arg1: u32,
    data_length: u32,
    data_check: u32,
    magic: u32,

    /// Initialize a new message header
    pub fn init(cmd: CommandType, arg0: u32, arg1: u32, data_length: u32) MessageHeader {
        const magic = @bitReverse(@intFromEnum(cmd));
        return MessageHeader{
            .command = cmd,
            .arg0 = arg0,
            .arg1 = arg1,
            .data_length = data_length,
            .data_check = 0, // Will be calculated later
            .magic = magic,
        };
    }

    /// Calculate the data checksum
    pub fn calculateChecksum(self: *MessageHeader, data: ?[]const u8) void {
        if (data) |d| {
            var checksum: u32 = 0;
            for (d) |byte| {
                checksum += byte;
            }
            self.data_check = checksum;
        } else {
            self.data_check = 0;
        }
    }

    /// Validate the message header
    pub fn validate(self: MessageHeader) bool {
        const expected_magic = @bitReverse(@intFromEnum(self.command));
        return self.magic == expected_magic;
    }
};

/// ADB connection string format
pub const ConnectionString = struct {
    pub const DEVICE_BANNER_PREFIX = "device::";
    pub const HOST_BANNER_PREFIX = "host::";
    pub const FEATURE_SHELL_V2 = "shell_v2";
    pub const FEATURE_CMD = "cmd";
    pub const FEATURE_STAT_V2 = "stat_v2";
    pub const FEATURE_APEX = "apex";
    pub const FEATURE_FIXED_PUSH_MKDIR = "fixed_push_mkdir";
    pub const FEATURE_ABB = "abb";
    pub const FEATURE_FIXED_PUSH_SYMLINK_TIMESTAMP = "fixed_push_symlink_timestamp";
};

/// ADB error types
pub const Error = error{
    ConnectionFailed,
    AuthenticationFailed,
    InvalidResponse,
    DeviceNotFound,
    CommandFailed,
    Timeout,
    InvalidArgument,
    OutOfMemory,
    PermissionDenied,
    UnsupportedOperation,
};
