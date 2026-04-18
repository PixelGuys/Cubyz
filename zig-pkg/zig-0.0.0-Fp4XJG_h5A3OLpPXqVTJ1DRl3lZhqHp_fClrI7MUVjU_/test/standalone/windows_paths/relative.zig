const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;
    const cwd_path = try std.process.currentPathAlloc(io, arena);

    if (args.len < 3) return error.MissingArgs;

    const relative = try std.fs.path.relative(arena, cwd_path, init.environ_map, args[1], args[2]);

    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &.{});
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(relative);
}
