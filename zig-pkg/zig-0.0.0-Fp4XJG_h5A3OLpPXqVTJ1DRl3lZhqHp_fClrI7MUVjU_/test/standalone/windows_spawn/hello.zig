const std = @import("std");

pub fn main() !void {
    const io = std.Options.debug_io;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &.{});
    const stdout = &stdout_writer.interface;
    try stdout.writeAll("hello from exe\n");
}
