//! Checks that the basename of the given path matches a string.
//!
//! Usage:
//!
//! ```
//! has_basename <path> <basename>
//! ```
//!
//! <path> must be absolute.
//!
//! Returns a non-zero exit code if basename
//! does not match the given string.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    _ = args.next() orelse unreachable; // skip binary name

    const path = args.next() orelse {
        std.log.err("missing <path> argument", .{});
        return error.BadUsage;
    };

    const basename = args.next() orelse {
        std.log.err("missing <basename> argument", .{});
        return error.BadUsage;
    };

    const actual_basename = std.fs.path.basename(path);
    if (std.mem.eql(u8, actual_basename, basename)) {
        return;
    }

    return error.NotEqual;
}
