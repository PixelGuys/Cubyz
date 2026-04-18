const std = @import("std");

/// Checks the existence of files relative to cwd.
/// A path starting with ! should not exist.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    var arg_it = try init.minimal.args.iterateAllocator(arena);
    _ = arg_it.next();

    const cwd = std.Io.Dir.cwd();
    const cwd_realpath = try cwd.realPathFileAlloc(io, ".", arena);

    while (arg_it.next()) |file_path| {
        if (file_path.len > 0 and file_path[0] == '!') {
            errdefer std.log.err(
                "exclusive file check '{s}{c}{s}' failed",
                .{ cwd_realpath, std.fs.path.sep, file_path[1..] },
            );
            if (cwd.statFile(io, file_path[1..], .{})) |_| {
                return error.FileFound;
            } else |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            }
        } else {
            errdefer std.log.err(
                "inclusive file check '{s}{c}{s}' failed",
                .{ cwd_realpath, std.fs.path.sep, file_path },
            );
            _ = try cwd.statFile(io, file_path, .{});
        }
    }
}
