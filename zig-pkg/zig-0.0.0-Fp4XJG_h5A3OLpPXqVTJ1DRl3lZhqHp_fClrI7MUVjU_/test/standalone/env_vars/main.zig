const std = @import("std");
const builtin = @import("builtin");

// Note: the environment variables under test are set by the build.zig
pub fn main(init: std.process.Init) !void {
    @setEvalBranchQuota(10000);

    const allocator = init.gpa;
    const arena = init.arena.allocator();
    const environ = init.minimal.environ;

    // containsUnempty
    {
        try std.testing.expect(try environ.containsUnempty(allocator, "FOO"));
        try std.testing.expect(!(try environ.containsUnempty(allocator, "FOO=")));
        try std.testing.expect(!(try environ.containsUnempty(allocator, "FO")));
        try std.testing.expect(!(try environ.containsUnempty(allocator, "FOOO")));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(try environ.containsUnempty(allocator, "foo"));
        }
        try std.testing.expect(try environ.containsUnempty(allocator, "EQUALS"));
        try std.testing.expect(!(try environ.containsUnempty(allocator, "EQUALS=ABC")));
        try std.testing.expect(try environ.containsUnempty(allocator, "КИРиллИЦА"));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(try environ.containsUnempty(allocator, "кирИЛЛица"));
        }
        try std.testing.expect(!(try environ.containsUnempty(allocator, "NO_VALUE")));
        try std.testing.expect(!(try environ.containsUnempty(allocator, "NOT_SET")));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(try environ.containsUnempty(allocator, "=HIDDEN"));
            try std.testing.expect(try environ.containsUnempty(allocator, "INVALID_UTF16_\xed\xa0\x80"));
        }
    }

    // containsUnemptyConstant
    {
        try std.testing.expect(environ.containsUnemptyConstant("FOO"));
        try std.testing.expect(!environ.containsUnemptyConstant("FOO="));
        try std.testing.expect(!environ.containsUnemptyConstant("FO"));
        try std.testing.expect(!environ.containsUnemptyConstant("FOOO"));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(environ.containsUnemptyConstant("foo"));
        }
        try std.testing.expect(environ.containsUnemptyConstant("EQUALS"));
        try std.testing.expect(!environ.containsUnemptyConstant("EQUALS=ABC"));
        try std.testing.expect(environ.containsUnemptyConstant("КИРиллИЦА"));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(environ.containsUnemptyConstant("кирИЛЛица"));
        }
        try std.testing.expect(!(environ.containsUnemptyConstant("NO_VALUE")));
        try std.testing.expect(!(environ.containsUnemptyConstant("NOT_SET")));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(environ.containsUnemptyConstant("=HIDDEN"));
            try std.testing.expect(environ.containsUnemptyConstant("INVALID_UTF16_\xed\xa0\x80"));
        }
    }

    // contains
    {
        try std.testing.expect(try environ.contains(allocator, "FOO"));
        try std.testing.expect(!(try environ.contains(allocator, "FOO=")));
        try std.testing.expect(!(try environ.contains(allocator, "FO")));
        try std.testing.expect(!(try environ.contains(allocator, "FOOO")));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(try environ.contains(allocator, "foo"));
        }
        try std.testing.expect(try environ.contains(allocator, "EQUALS"));
        try std.testing.expect(!(try environ.contains(allocator, "EQUALS=ABC")));
        try std.testing.expect(try environ.contains(allocator, "КИРиллИЦА"));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(try environ.contains(allocator, "кирИЛЛица"));
        }
        try std.testing.expect(try environ.contains(allocator, "NO_VALUE"));
        try std.testing.expect(!(try environ.contains(allocator, "NOT_SET")));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(try environ.contains(allocator, "=HIDDEN"));
            try std.testing.expect(try environ.contains(allocator, "INVALID_UTF16_\xed\xa0\x80"));
        }
    }

    // containsConstant
    {
        try std.testing.expect(environ.containsConstant("FOO"));
        try std.testing.expect(!environ.containsConstant("FOO="));
        try std.testing.expect(!environ.containsConstant("FO"));
        try std.testing.expect(!environ.containsConstant("FOOO"));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(environ.containsConstant("foo"));
        }
        try std.testing.expect(environ.containsConstant("EQUALS"));
        try std.testing.expect(!environ.containsConstant("EQUALS=ABC"));
        try std.testing.expect(environ.containsConstant("КИРиллИЦА"));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(environ.containsConstant("кирИЛЛица"));
        }
        try std.testing.expect(environ.containsConstant("NO_VALUE"));
        try std.testing.expect(!(environ.containsConstant("NOT_SET")));
        if (builtin.os.tag == .windows) {
            try std.testing.expect(environ.containsConstant("=HIDDEN"));
            try std.testing.expect(environ.containsConstant("INVALID_UTF16_\xed\xa0\x80"));
        }
    }

    // getAlloc
    {
        try std.testing.expectEqualSlices(u8, "123", try environ.getAlloc(arena, "FOO"));
        try std.testing.expectError(error.EnvironmentVariableMissing, environ.getAlloc(arena, "FOO="));
        try std.testing.expectError(error.EnvironmentVariableMissing, environ.getAlloc(arena, "FO"));
        try std.testing.expectError(error.EnvironmentVariableMissing, environ.getAlloc(arena, "FOOO"));
        if (builtin.os.tag == .windows) {
            try std.testing.expectEqualSlices(u8, "123", try environ.getAlloc(arena, "foo"));
        }
        try std.testing.expectEqualSlices(u8, "ABC=123", try environ.getAlloc(arena, "EQUALS"));
        try std.testing.expectError(error.EnvironmentVariableMissing, environ.getAlloc(arena, "EQUALS=ABC"));
        try std.testing.expectEqualSlices(u8, "non-ascii አማርኛ \u{10FFFF}", try environ.getAlloc(arena, "КИРиллИЦА"));
        if (builtin.os.tag == .windows) {
            try std.testing.expectEqualSlices(u8, "non-ascii አማርኛ \u{10FFFF}", try environ.getAlloc(arena, "кирИЛЛица"));
        }
        try std.testing.expectEqualSlices(u8, "", try environ.getAlloc(arena, "NO_VALUE"));
        try std.testing.expectError(error.EnvironmentVariableMissing, environ.getAlloc(arena, "NOT_SET"));
        if (builtin.os.tag == .windows) {
            try std.testing.expectEqualSlices(u8, "hi", try environ.getAlloc(arena, "=HIDDEN"));
            try std.testing.expectEqualSlices(u8, "\xed\xa0\x80", try environ.getAlloc(arena, "INVALID_UTF16_\xed\xa0\x80"));
        }
    }

    // Environ.Map
    {
        var environ_map = try environ.createMap(allocator);
        defer environ_map.deinit();

        try std.testing.expectEqualSlices(u8, "123", environ_map.get("FOO").?);
        try std.testing.expectEqual(null, environ_map.get("FO"));
        try std.testing.expectEqual(null, environ_map.get("FOOO"));
        if (builtin.os.tag == .windows) {
            try std.testing.expectEqualSlices(u8, "123", environ_map.get("foo").?);
        }
        try std.testing.expectEqualSlices(u8, "ABC=123", environ_map.get("EQUALS").?);
        try std.testing.expectEqual(null, environ_map.get("EQUALS=ABC"));
        try std.testing.expectEqualSlices(u8, "non-ascii አማርኛ \u{10FFFF}", environ_map.get("КИРиллИЦА").?);
        if (builtin.os.tag == .windows) {
            try std.testing.expectEqualSlices(u8, "non-ascii አማርኛ \u{10FFFF}", environ_map.get("кирИЛЛица").?);
        }
        try std.testing.expectEqualSlices(u8, "", environ_map.get("NO_VALUE").?);
        try std.testing.expectEqual(null, environ_map.get("NOT_SET"));
        if (builtin.os.tag == .windows) {
            try std.testing.expectEqualSlices(u8, "hi", environ_map.get("=HIDDEN").?);
            try std.testing.expectEqualSlices(u8, "\xed\xa0\x80", environ_map.get("INVALID_UTF16_\xed\xa0\x80").?);
        }
    }
}
