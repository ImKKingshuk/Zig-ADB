# Zig-ADB

An implementation of the Android Debug Bridge (ADB) protocol in the Zig programming language.

## Overview

Zig-ADB is a native implementation of the ADB protocol that allows communication with Android devices. It provides a command-line interface similar to the original ADB tool but implemented in Zig for better performance, memory safety, and cross-platform compatibility.

## Features

- Device discovery and management
- Shell command execution
- File transfer (push/pull)
- Multiple transport types (USB, TCP/IP)
- ADB protocol implementation

## Building

```bash
zig build
```

## Usage

```bash
zig-adb [options] <command> [command-arguments]
```

### Options

- `-s <serial>`: Use device with the given serial
- `-d`: Use the first USB device
- `-e`: Use the first emulator
- `-t <transport>`: Use the given transport (usb, local, tcp)
- `-H <host>`: Name of adb server host (default: localhost)
- `-P <port>`: Port of adb server (default: 5037)

### Commands

- `devices [-l]`: List connected devices (-l for long output)
- `shell [<command>]`: Run remote shell command
- `push <local> <remote>`: Copy file/dir to device
- `version`: Show version
- `help`: Show help message

## License

GNU General Public License v3.0
