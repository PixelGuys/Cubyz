//! test getting environment variables

const std = @import("std");
const builtin = @import("builtin");

pub fn main(init: std.process.Init.Minimal) !void {
    if (builtin.target.os.tag == .windows) return;
    if (builtin.target.os.tag == .wasi and !builtin.link_libc) return;

    const environ = init.environ;

    // Test some unset env vars:
    try std.testing.expectEqual(environ.getPosix(""), null);
    try std.testing.expectEqual(environ.getPosix("BOGUSDOESNOTEXISTENVVAR"), null);
    try std.testing.expectEqual(environ.getPosix("BOGUSDOESNOTEXISTENVVAR"), null);

    if (builtin.link_libc) {
        // Test if USER matches what C library sees
        const expected = std.mem.span(std.c.getenv("USER") orelse "");
        const actual = environ.getPosix("USER") orelse "";
        try std.testing.expectEqualStrings(expected, actual);
    }

    // env vars set by our build.zig run step:
    try std.testing.expectEqualStrings("", environ.getPosix("ZIG_TEST_POSIX_EMPTY") orelse "invalid");
    try std.testing.expectEqualStrings("test=variable", environ.getPosix("ZIG_TEST_POSIX_1EQ") orelse "invalid");
    try std.testing.expectEqualStrings("=test=variable=", environ.getPosix("ZIG_TEST_POSIX_3EQ") orelse "invalid");
}
