//! This script updates the .c, .h, .s, and .S files that make up the start
//! files such as crt1.o.
//!
//! Example usage:
//! `zig run tools/update_freebsd_libc.zig -- ~/Downloads/freebsd-src .`

const std = @import("std");
const Io = std.Io;

const exempt_files = [_][]const u8{
    // This file is maintained by a separate project and does not come from FreeBSD.
    "abilists",
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    const freebsd_src_path = args[1];
    const zig_src_path = args[2];

    const dest_dir_path = try std.fmt.allocPrint(arena, "{s}/lib/libc/freebsd", .{zig_src_path});

    var dest_dir = Io.Dir.cwd().openDir(io, dest_dir_path, .{ .iterate = true }) catch |err| {
        std.log.err("unable to open destination directory '{s}': {t}", .{ dest_dir_path, err });
        std.process.exit(1);
    };
    defer dest_dir.close(io);

    var freebsd_src_dir = try Io.Dir.cwd().openDir(io, freebsd_src_path, .{});
    defer freebsd_src_dir.close(io);

    // Copy updated files from upstream.
    {
        var walker = try dest_dir.walk(arena);
        defer walker.deinit();

        walk: while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (std.mem.startsWith(u8, entry.basename, ".")) continue;
            for (exempt_files) |p| {
                if (std.mem.eql(u8, entry.path, p)) continue :walk;
            }

            std.log.info("updating '{s}/{s}' from '{s}/{s}'", .{
                dest_dir_path, entry.path, freebsd_src_path, entry.path,
            });

            freebsd_src_dir.copyFile(entry.path, dest_dir, entry.path, io, .{}) catch |err| {
                std.log.warn("unable to copy '{s}/{s}' to '{s}/{s}': {t}", .{
                    freebsd_src_path, entry.path, dest_dir_path, entry.path, err,
                });
                if (err == error.FileNotFound) {
                    try dest_dir.deleteFile(io, entry.path);
                }
            };
        }
    }
}
