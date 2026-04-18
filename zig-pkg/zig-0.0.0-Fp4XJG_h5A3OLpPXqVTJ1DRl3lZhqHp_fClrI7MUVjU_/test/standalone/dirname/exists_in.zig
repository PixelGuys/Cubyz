//! Verifies that a file exists in a directory.
//!
//! Usage:
//!
//! ```
//! exists_in <dir> <path>
//! ```
//!
//! Where `<dir>/<path>` is the full path to the file.
//! `<dir>` must be an absolute path.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    _ = args.next() orelse unreachable; // skip binary name

    const dir_path = args.next() orelse {
        std.log.err("missing <dir> argument", .{});
        return error.BadUsage;
    };

    const relpath = args.next() orelse {
        std.log.err("missing <path> argument", .{});
        return error.BadUsage;
    };

    const io = std.Io.Threaded.global_single_threaded.io();

    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{});
    defer dir.close(io);

    _ = try dir.statFile(io, relpath, .{});
}
