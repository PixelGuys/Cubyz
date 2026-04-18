pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len != 2) return error.BadUsage;
    const path = args[1];

    const io = std.Io.Threaded.global_single_threaded.io();

    std.Io.Dir.cwd().access(io, path, .{}) catch return error.AccessFailed;
}

const std = @import("std");
