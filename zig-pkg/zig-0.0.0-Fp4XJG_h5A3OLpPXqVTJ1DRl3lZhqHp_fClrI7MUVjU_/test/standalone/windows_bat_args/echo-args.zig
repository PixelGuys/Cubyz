const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &.{});
    const stdout = &stdout_writer.interface;
    for (args[1..], 1..) |arg, i| {
        try stdout.writeAll(arg);
        if (i != args.len - 1) try stdout.writeByte('\x00');
    }
}
