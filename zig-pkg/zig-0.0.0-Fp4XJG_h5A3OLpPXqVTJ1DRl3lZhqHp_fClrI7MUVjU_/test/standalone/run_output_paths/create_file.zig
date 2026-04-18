const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var args = try init.minimal.args.iterateAllocator(init.arena.allocator());
    _ = args.skip();
    const dir_name = args.next().?;
    const dir = try std.Io.Dir.cwd().openDir(io, if (std.mem.startsWith(u8, dir_name, "--dir="))
        dir_name["--dir=".len..]
    else
        dir_name, .{});
    const file_name = args.next().?;
    const file = try dir.createFile(io, file_name, .{});
    var file_writer = file.writer(io, &.{});
    try file_writer.interface.print(
        \\{s}
        \\{s}
        \\Hello, world!
        \\
    , .{ dir_name, file_name });
}
