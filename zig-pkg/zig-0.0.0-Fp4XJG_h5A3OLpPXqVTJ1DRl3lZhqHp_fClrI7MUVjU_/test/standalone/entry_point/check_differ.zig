const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len != 3) return error.BadUsage; // usage: 'check_differ <path a> <path b>'

    const contents_1 = try std.Io.Dir.cwd().readFileAlloc(io, args[1], arena, .limited(1024 * 1024 * 64)); // 64 MiB ought to be plenty
    const contents_2 = try std.Io.Dir.cwd().readFileAlloc(io, args[2], arena, .limited(1024 * 1024 * 64)); // 64 MiB ought to be plenty

    if (std.mem.eql(u8, contents_1, contents_2)) {
        return error.FilesMatch;
    }
    // success, files differ
}
