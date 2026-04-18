// Test relative paths through POSIX APIS.  These tests have to change the cwd, so
// they shouldn't be Zig unit tests.

const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    if (builtin.target.os.tag == .wasi) return; // Can link, but can't change into tmpDir

    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const tmp_dir_path = args[1];

    var tmp_dir = try Io.Dir.cwd().openDir(io, tmp_dir_path, .{});
    defer tmp_dir.close(io);

    // Want to test relative paths, so cd into the tmpdir for these tests
    try std.process.setCurrentDir(io, tmp_dir);

    try test_link(io, tmp_dir);
}

fn test_link(io: Io, tmp_dir: Io.Dir) !void {
    switch (builtin.target.os.tag) {
        .linux, .illumos => {},
        else => return,
    }

    const target_name = "link-target";
    const link_name = "newlink";

    try tmp_dir.writeFile(io, .{ .sub_path = target_name, .data = "example" });

    // Test 1: create the relative link from inside tmp_dir
    try Io.Dir.hardLink(.cwd(), target_name, .cwd(), link_name, io, .{});

    // Verify
    const efd = try tmp_dir.openFile(io, target_name, .{});
    defer efd.close(io);

    const nfd = try tmp_dir.openFile(io, link_name, .{});
    defer nfd.close(io);

    {
        const e_stat = try efd.stat(io);
        const n_stat = try nfd.stat(io);
        try std.testing.expectEqual(e_stat.inode, n_stat.inode);
        try std.testing.expectEqual(2, n_stat.nlink);
    }

    // Test 2: Remove the link and see the stats update
    try Io.Dir.cwd().deleteFile(io, link_name);
    {
        const e_stat = try efd.stat(io);
        try std.testing.expectEqual(1, e_stat.nlink);
    }
}
