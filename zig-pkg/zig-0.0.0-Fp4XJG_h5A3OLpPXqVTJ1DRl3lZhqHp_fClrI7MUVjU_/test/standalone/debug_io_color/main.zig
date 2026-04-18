const std = @import("std");

pub fn main() !void {
    const stderr = std.debug.lockStderr(&.{});
    defer std.debug.unlockStderr();
    try std.Io.File.stdout().writeStreamingAll(std.Options.debug_io, if (stderr.terminal_mode != .no_color) "true" else "false");
}
