const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    var it = try init.minimal.args.iterateAllocator(gpa);
    defer it.deinit();
    _ = it.next() orelse unreachable; // skip binary name
    const exe_path = it.next() orelse unreachable;
    const symlink_path = it.next() orelse unreachable;

    const cwd = try std.process.currentPathAlloc(io, init.arena.allocator());

    // If `exe_path` is relative to our cwd, we need to convert it to be relative to the dirname of `symlink_path`.
    const exe_rel_path = try std.fs.path.relative(gpa, cwd, init.environ_map, std.fs.path.dirname(symlink_path) orelse ".", exe_path);
    defer gpa.free(exe_rel_path);

    try std.Io.Dir.cwd().symLink(io, exe_rel_path, symlink_path, .{});
}
