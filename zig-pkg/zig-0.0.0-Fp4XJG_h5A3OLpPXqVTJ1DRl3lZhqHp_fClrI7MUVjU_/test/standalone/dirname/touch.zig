//! Creates a file at the given path, if it doesn't already exist.
//!
//! ```
//! touch <path>
//! ```
//!
//! Path must be absolute.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    _ = args.next() orelse unreachable; // skip binary name

    const path = args.next() orelse {
        std.log.err("missing <path> argument", .{});
        return error.BadUsage;
    };

    const dir_path = std.Io.Dir.path.dirname(path) orelse unreachable;
    const basename = std.Io.Dir.path.basename(path);

    const io = std.Io.Threaded.global_single_threaded.io();

    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{});
    defer dir.close(io);

    _ = dir.statFile(io, basename, .{}) catch {
        var file = try dir.createFile(io, basename, .{});
        file.close(io);
    };
}
