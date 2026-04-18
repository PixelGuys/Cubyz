const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Target = std.Target;
const Version = std.SemanticVersion;

pub const macos = @import("darwin/macos.zig");

/// Check if SDK is installed on Darwin without triggering CLT installation popup window.
///
/// Simply invoking `xcrun` will inevitably trigger the CLT installation popup.
/// Therefore, we resort to invoking `xcode-select --print-path` and checking
/// if the status is nonzero.
///
/// stderr from xcode-select is ignored.
///
/// If error.OutOfMemory occurs in Allocator, this function returns null.
pub fn isSdkInstalled(gpa: Allocator, io: Io) bool {
    const result = std.process.run(gpa, io, .{
        .argv = &.{ "xcode-select", "--print-path" },
    }) catch return false;
    defer {
        gpa.free(result.stderr);
        gpa.free(result.stdout);
    }
    return switch (result.term) {
        .exited => |code| if (code == 0) result.stdout.len > 0 else false,
        else => false,
    };
}

/// Detect SDK on Darwin.
/// Calls `xcrun --sdk <target_sdk> --show-sdk-path` which fetches the path to the SDK.
/// Caller owns the memory.
/// stderr from xcrun is ignored.
/// If error.OutOfMemory occurs in Allocator, this function returns null.
pub fn getSdk(gpa: Allocator, io: Io, target: *const Target) ?[]const u8 {
    const is_simulator_abi = target.abi == .simulator;
    const sdk = switch (target.os.tag) {
        .driverkit => "driverkit",
        .ios => if (is_simulator_abi) "iphonesimulator" else "iphoneos",
        .maccatalyst, .macos => "macosx",
        .tvos => if (is_simulator_abi) "appletvsimulator" else "appletvos",
        .visionos => if (is_simulator_abi) "xrsimulator" else "xros",
        .watchos => if (is_simulator_abi) "watchsimulator" else "watchos",
        else => return null,
    };
    const argv = &[_][]const u8{ "xcrun", "--sdk", sdk, "--show-sdk-path" };
    const result = std.process.run(gpa, io, .{ .argv = argv }) catch return null;
    defer {
        gpa.free(result.stderr);
        gpa.free(result.stdout);
    }
    switch (result.term) {
        .exited => |code| if (code != 0) return null,
        else => return null,
    }
    return gpa.dupe(u8, mem.trimEnd(u8, result.stdout, "\r\n")) catch null;
}

test {
    _ = macos;
}
