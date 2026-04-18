const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var args = try init.minimal.args.iterateAllocator(init.arena.allocator());
    _ = args.skip();
    const filename = args.next().?;
    const file = try std.Io.Dir.cwd().createFile(io, filename, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, filename);
}
