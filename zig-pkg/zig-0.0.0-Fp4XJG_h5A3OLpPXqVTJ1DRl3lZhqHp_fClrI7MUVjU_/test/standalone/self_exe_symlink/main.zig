const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const self_path = try std.process.executablePathAlloc(io, gpa);
    defer gpa.free(self_path);

    var self_exe = try std.process.openExecutable(io, .{});
    defer self_exe.close(io);

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const self_exe_path = buf[0..try self_exe.realPath(io, &buf)];

    try std.testing.expectEqualStrings(self_exe_path, self_path);
}
