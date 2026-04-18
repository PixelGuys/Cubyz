//! Tests belong here if they access internal state of std.Io.Threaded or
//! otherwise assume details of that particular implementation.
const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const testing = std.testing;
const assert = std.debug.assert;
const windows = std.os.windows;

test "concurrent vs main prevents deadlock via oversubscription" {
    var threaded: Io.Threaded = .init(std.testing.allocator, .{
        .argv0 = .empty,
        .environ = .empty,
    });
    defer threaded.deinit();
    const io = threaded.io();

    threaded.async_limit = .nothing;

    var queue: Io.Queue(u8) = .init(&.{});

    var putter = io.concurrent(put, .{ io, &queue }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => {
            try testing.expect(builtin.single_threaded);
            return;
        },
    };
    defer putter.cancel(io);

    try testing.expectEqual(42, queue.getOneUncancelable(io));
}

fn put(io: Io, queue: *Io.Queue(u8)) void {
    queue.putOneUncancelable(io, 42) catch unreachable;
}

fn get(io: Io, queue: *Io.Queue(u8)) void {
    assert(queue.getOneUncancelable(io) catch unreachable == 42);
}

test "concurrent vs concurrent prevents deadlock via oversubscription" {
    var threaded: Io.Threaded = .init(std.testing.allocator, .{
        .argv0 = .empty,
        .environ = .empty,
    });
    defer threaded.deinit();
    const io = threaded.io();

    threaded.async_limit = .nothing;

    var queue: Io.Queue(u8) = .init(&.{});

    var putter = io.concurrent(put, .{ io, &queue }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => {
            try testing.expect(builtin.single_threaded);
            return;
        },
    };
    defer putter.cancel(io);

    var getter = try io.concurrent(get, .{ io, &queue });
    defer getter.cancel(io);

    getter.await(io);
    putter.await(io);
}

const ByteArray256 = struct { x: [32]u8 align(32) };
const ByteArray512 = struct { x: [64]u8 align(64) };

fn concatByteArrays(a: ByteArray256, b: ByteArray256) ByteArray512 {
    return .{ .x = a.x ++ b.x };
}

test "async/concurrent context and result alignment" {
    var buffer: [2048]u8 align(@alignOf(ByteArray512)) = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buffer);

    var threaded: std.Io.Threaded = .init(fba.allocator(), .{
        .argv0 = .empty,
        .environ = .empty,
    });
    defer threaded.deinit();
    const io = threaded.io();

    const a: ByteArray256 = .{ .x = @splat(2) };
    const b: ByteArray256 = .{ .x = @splat(3) };
    const expected: ByteArray512 = .{ .x = @as([32]u8, @splat(2)) ++ @as([32]u8, @splat(3)) };

    {
        var future = io.async(concatByteArrays, .{ a, b });
        const result = future.await(io);
        try std.testing.expectEqualSlices(u8, &expected.x, &result.x);
    }
    {
        var future = io.concurrent(concatByteArrays, .{ a, b }) catch |err| switch (err) {
            error.ConcurrencyUnavailable => {
                try testing.expect(builtin.single_threaded);
                return;
            },
        };
        const result = future.await(io);
        try std.testing.expectEqualSlices(u8, &expected.x, &result.x);
    }
}

fn concatByteArraysResultPtr(a: ByteArray256, b: ByteArray256, result: *ByteArray512) void {
    result.* = .{ .x = a.x ++ b.x };
}

test "Group.async context alignment" {
    var buffer: [2048]u8 align(@alignOf(ByteArray512)) = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buffer);

    var threaded: std.Io.Threaded = .init(fba.allocator(), .{
        .argv0 = .empty,
        .environ = .empty,
    });
    defer threaded.deinit();
    const io = threaded.io();

    const a: ByteArray256 = .{ .x = @splat(2) };
    const b: ByteArray256 = .{ .x = @splat(3) };
    const expected: ByteArray512 = .{ .x = @as([32]u8, @splat(2)) ++ @as([32]u8, @splat(3)) };

    var group: std.Io.Group = .init;
    var result: ByteArray512 = undefined;
    group.async(io, concatByteArraysResultPtr, .{ a, b, &result });
    try group.await(io);
    try std.testing.expectEqualSlices(u8, &expected.x, &result.x);
}

fn returnArray() [32]u8 {
    return @splat(5);
}

test "async with array return type" {
    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{
        .argv0 = .empty,
        .environ = .empty,
    });
    defer threaded.deinit();
    const io = threaded.io();

    var future = io.async(returnArray, .{});
    const result = future.await(io);
    try std.testing.expectEqualSlices(u8, &@as([32]u8, @splat(5)), &result);
}

test "cancel blocked read from pipe" {
    const global = struct {
        fn readFromPipe(io: Io, pipe: Io.File) !void {
            var buf: [1]u8 = undefined;
            if (pipe.readStreaming(io, &.{&buf})) |_| {
                return error.UnexpectedData;
            } else |err| switch (err) {
                error.Canceled => return,
                else => |e| return e,
            }
        }
    };

    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{
        .argv0 = .empty,
        .environ = .empty,
    });
    defer threaded.deinit();
    const io = threaded.io();

    var read_end: Io.File = undefined;
    var write_end: Io.File = undefined;
    switch (builtin.target.os.tag) {
        .wasi => return error.SkipZigTest,
        .windows => {
            const pipe = try threaded.windowsCreatePipe(.{
                .server = .{ .mode = .{ .IO = .SYNCHRONOUS_NONALERT } },
                .client = .{ .mode = .{ .IO = .SYNCHRONOUS_NONALERT } },
                .inbound = true,
            });
            read_end = .{ .handle = pipe[0], .flags = .{ .nonblocking = false } };
            write_end = .{ .handle = pipe[1], .flags = .{ .nonblocking = false } };
        },
        else => {
            const pipe = try std.Io.Threaded.pipe2(.{ .CLOEXEC = true });
            read_end = .{ .handle = pipe[0], .flags = .{ .nonblocking = false } };
            write_end = .{ .handle = pipe[1], .flags = .{ .nonblocking = false } };
        },
    }
    defer {
        read_end.close(io);
        write_end.close(io);
    }

    var future = io.concurrent(global.readFromPipe, .{ io, read_end }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    defer _ = future.cancel(io) catch {};
    try io.sleep(.fromMilliseconds(10), .awake);
    try future.cancel(io);
}

test "memory mapping fallback" {
    if (builtin.os.tag == .wasi and builtin.link_libc) {
        // https://github.com/ziglang/zig/issues/20747 (open fd does not have write permission)
        return error.SkipZigTest;
    }

    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{
        .argv0 = .empty,
        .environ = .empty,
        .disable_memory_mapping = true,
    });
    defer threaded.deinit();
    const io = threaded.io();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{
        .sub_path = "blah.txt",
        .data = "this is my data123",
    });

    {
        var file = try tmp.dir.openFile(io, "blah.txt", .{ .mode = .read_write });
        defer file.close(io);

        // The `Io.File.MemoryMap` API does not specify what happens if we supply a
        // length greater than file size, but this is testing specifically std.Io.Threaded
        // with disable_memory_mapping = true.
        var mm = try file.createMemoryMap(io, .{ .len = "this is my data123".len + 3 });
        defer mm.destroy(io);

        try testing.expectEqualStrings("this is my data123\x00\x00\x00", mm.memory);
        mm.memory[4] = '9';
        mm.memory[7] = '9';

        try mm.write(io);
    }

    var buffer: [100]u8 = undefined;
    const updated_contents = try tmp.dir.readFile(io, "blah.txt", &buffer);
    try testing.expectEqualStrings("this9is9my data123\x00\x00\x00", updated_contents);

    {
        var file = try tmp.dir.openFile(io, "blah.txt", .{ .mode = .read_only });
        defer file.close(io);

        var mm = try file.createMemoryMap(io, .{
            .len = "this9is9my".len,
            .protection = .{ .read = true },
        });
        defer mm.destroy(io);

        try testing.expectEqualStrings("this9is9my", mm.memory);

        const new_len = "this9is9my data123".len;
        mm.setLength(io, new_len) catch |err| switch (err) {
            error.OperationUnsupported => {
                mm.destroy(io);
                mm = try file.createMemoryMap(io, .{ .len = new_len });
            },
            else => |e| return e,
        };
        try mm.read(io);

        try testing.expectEqualStrings("this9is9my data123", mm.memory);
    }
}

/// Wrapper around RtlDosPathNameToNtPathName_U for use in comparing
/// the behavior of RtlDosPathNameToNtPathName_U with wToPrefixedFileW
/// Note: RtlDosPathNameToNtPathName_U is not used in the Zig implementation
///       because it allocates.
fn RtlDosPathNameToNtPathName_U(path: [:0]const u16) !Io.Threaded.WindowsPathSpace {
    var out: windows.UNICODE_STRING = undefined;
    if (!windows.ntdll.RtlDosPathNameToNtPathName_U(path, &out, null, null).toBool()) return error.BadPathName;
    defer windows.ntdll.RtlFreeUnicodeString(&out);

    var path_space: Io.Threaded.WindowsPathSpace = undefined;
    const out_path = out.slice();
    @memcpy(path_space.data[0..out_path.len], out_path);
    path_space.len = out.Length / 2;
    path_space.data[path_space.len] = 0;

    return path_space;
}

/// Test that the Zig conversion matches the expected_path (for instances where
/// the Zig implementation intentionally diverges from what RtlDosPathNameToNtPathName_U does).
fn testToPrefixedFileNoOracle(comptime path: []const u8, comptime expected_path: []const u8) !void {
    const path_utf16 = std.unicode.utf8ToUtf16LeStringLiteral(path);
    const expected_path_utf16 = std.unicode.utf8ToUtf16LeStringLiteral(expected_path);
    const actual_path = try Io.Threaded.wToPrefixedFileW(null, path_utf16, .{});
    std.testing.expectEqualSlices(u16, expected_path_utf16, actual_path.span()) catch |e| {
        std.debug.print("got '{f}', expected '{f}'\n", .{ std.unicode.fmtUtf16Le(actual_path.span()), std.unicode.fmtUtf16Le(expected_path_utf16) });
        return e;
    };
}

/// Test that the Zig conversion matches the expected_path and that the
/// expected_path matches the conversion that RtlDosPathNameToNtPathName_U does.
fn testToPrefixedFileWithOracle(comptime path: []const u8, comptime expected_path: []const u8) !void {
    try testToPrefixedFileNoOracle(path, expected_path);
    try testToPrefixedFileOnlyOracle(path);
}

/// Test that the Zig conversion matches the conversion that RtlDosPathNameToNtPathName_U does.
fn testToPrefixedFileOnlyOracle(comptime path: []const u8) !void {
    const path_utf16 = std.unicode.utf8ToUtf16LeStringLiteral(path);
    const zig_result = try Io.Threaded.wToPrefixedFileW(null, path_utf16, .{});
    const win32_api_result = try RtlDosPathNameToNtPathName_U(path_utf16);
    std.testing.expectEqualSlices(u16, win32_api_result.span(), zig_result.span()) catch |e| {
        std.debug.print("got '{f}', expected '{f}'\n", .{ std.unicode.fmtUtf16Le(zig_result.span()), std.unicode.fmtUtf16Le(win32_api_result.span()) });
        return e;
    };
}

test "toPrefixedFileW" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Most test cases come from https://googleprojectzero.blogspot.com/2016/02/the-definitive-guide-on-win32-to-nt.html
    // Note that these tests do not actually touch the filesystem or care about whether or not
    // any of the paths actually exist or are otherwise valid.

    // Drive Absolute
    try testToPrefixedFileWithOracle("X:\\ABC\\DEF", "\\??\\X:\\ABC\\DEF");
    try testToPrefixedFileWithOracle("X:\\", "\\??\\X:\\");
    try testToPrefixedFileWithOracle("X:\\ABC\\", "\\??\\X:\\ABC\\");
    // Trailing . and space characters are stripped
    try testToPrefixedFileWithOracle("X:\\ABC\\DEF. .", "\\??\\X:\\ABC\\DEF");
    try testToPrefixedFileWithOracle("X:/ABC/DEF", "\\??\\X:\\ABC\\DEF");
    try testToPrefixedFileWithOracle("X:\\ABC\\..\\XYZ", "\\??\\X:\\XYZ");
    try testToPrefixedFileWithOracle("X:\\ABC\\..\\..\\..", "\\??\\X:\\");
    // Drive letter casing is unchanged
    try testToPrefixedFileWithOracle("x:\\", "\\??\\x:\\");

    // Drive Relative
    // These tests depend on the CWD of the specified drive letter which can vary,
    // so instead we just test that the Zig implementation matches the result of
    // RtlDosPathNameToNtPathName_U.
    // TODO: Setting the =X: environment variable didn't seem to affect
    //       RtlDosPathNameToNtPathName_U, not sure why that is but getting that
    //       to work could be an avenue to making these cases environment-independent.
    // All -> are examples of the result if the X drive's cwd was X:\ABC
    try testToPrefixedFileOnlyOracle("X:DEF\\GHI"); // -> \??\X:\ABC\DEF\GHI
    try testToPrefixedFileOnlyOracle("X:"); // -> \??\X:\ABC
    try testToPrefixedFileOnlyOracle("X:DEF. ."); // -> \??\X:\ABC\DEF
    try testToPrefixedFileOnlyOracle("X:ABC\\..\\XYZ"); // -> \??\X:\ABC\XYZ
    try testToPrefixedFileOnlyOracle("X:ABC\\..\\..\\.."); // -> \??\X:\
    try testToPrefixedFileOnlyOracle("x:"); // -> \??\X:\ABC

    // Rooted
    // These tests depend on the drive letter of the CWD which can vary, so
    // instead we just test that the Zig implementation matches the result of
    // RtlDosPathNameToNtPathName_U.
    // TODO: Getting the CWD path, getting the drive letter from it, and using it to
    //       construct the expected NT paths could be an avenue to making these cases
    //       environment-independent and therefore able to use testToPrefixedFileWithOracle.
    // All -> are examples of the result if the CWD's drive letter was X
    try testToPrefixedFileOnlyOracle("\\ABC\\DEF"); // -> \??\X:\ABC\DEF
    try testToPrefixedFileOnlyOracle("\\"); // -> \??\X:\
    try testToPrefixedFileOnlyOracle("\\ABC\\DEF. ."); // -> \??\X:\ABC\DEF
    try testToPrefixedFileOnlyOracle("/ABC/DEF"); // -> \??\X:\ABC\DEF
    try testToPrefixedFileOnlyOracle("\\ABC\\..\\XYZ"); // -> \??\X:\XYZ
    try testToPrefixedFileOnlyOracle("\\ABC\\..\\..\\.."); // -> \??\X:\

    // Relative
    // These cases differ in functionality to RtlDosPathNameToNtPathName_U.
    // Relative paths remain relative if they don't have enough .. components
    // to error with TooManyParentDirs
    try testToPrefixedFileNoOracle("ABC\\DEF", "ABC\\DEF");
    // TODO: enable this if trailing . and spaces are stripped from relative paths
    //try testToPrefixedFileNoOracle("ABC\\DEF. .", "ABC\\DEF");
    try testToPrefixedFileNoOracle("ABC/DEF", "ABC\\DEF");
    try testToPrefixedFileNoOracle("./ABC/.././DEF", "DEF");
    // TooManyParentDirs, so resolved relative to the CWD
    // All -> are examples of the result if the CWD was X:\ABC\DEF
    try testToPrefixedFileOnlyOracle("..\\GHI"); // -> \??\X:\ABC\GHI
    try testToPrefixedFileOnlyOracle("GHI\\..\\..\\.."); // -> \??\X:\

    // UNC Absolute
    try testToPrefixedFileWithOracle("\\\\server\\share\\ABC\\DEF", "\\??\\UNC\\server\\share\\ABC\\DEF");
    try testToPrefixedFileWithOracle("\\\\server", "\\??\\UNC\\server");
    try testToPrefixedFileWithOracle("\\\\server\\share", "\\??\\UNC\\server\\share");
    try testToPrefixedFileWithOracle("\\\\server\\share\\ABC. .", "\\??\\UNC\\server\\share\\ABC");
    try testToPrefixedFileWithOracle("//server/share/ABC/DEF", "\\??\\UNC\\server\\share\\ABC\\DEF");
    try testToPrefixedFileWithOracle("\\\\server\\share\\ABC\\..\\XYZ", "\\??\\UNC\\server\\share\\XYZ");
    try testToPrefixedFileWithOracle("\\\\server\\share\\ABC\\..\\..\\..", "\\??\\UNC\\server\\share");

    // Local Device
    try testToPrefixedFileWithOracle("\\\\.\\COM20", "\\??\\COM20");
    try testToPrefixedFileWithOracle("\\\\.\\pipe\\mypipe", "\\??\\pipe\\mypipe");
    try testToPrefixedFileWithOracle("\\\\.\\X:\\ABC\\DEF. .", "\\??\\X:\\ABC\\DEF");
    try testToPrefixedFileWithOracle("\\\\.\\X:/ABC/DEF", "\\??\\X:\\ABC\\DEF");
    try testToPrefixedFileWithOracle("\\\\.\\X:\\ABC\\..\\XYZ", "\\??\\X:\\XYZ");
    // Can replace the first component of the path (contrary to drive absolute and UNC absolute paths)
    try testToPrefixedFileWithOracle("\\\\.\\X:\\ABC\\..\\..\\C:\\", "\\??\\C:\\");
    try testToPrefixedFileWithOracle("\\\\.\\pipe\\mypipe\\..\\notmine", "\\??\\pipe\\notmine");

    // Special-case device names
    // TODO: Enable once these are supported
    //       more cases to test here: https://googleprojectzero.blogspot.com/2016/02/the-definitive-guide-on-win32-to-nt.html
    //try testToPrefixedFileWithOracle("COM1", "\\??\\COM1");
    // Sometimes the special-cased device names are not respected
    try testToPrefixedFileWithOracle("\\\\.\\X:\\COM1", "\\??\\X:\\COM1");
    try testToPrefixedFileWithOracle("\\\\abc\\xyz\\COM1", "\\??\\UNC\\abc\\xyz\\COM1");

    // Verbatim
    // Left untouched except \\?\ is replaced by \??\
    try testToPrefixedFileWithOracle("\\\\?\\X:", "\\??\\X:");
    try testToPrefixedFileWithOracle("\\\\?\\X:\\COM1", "\\??\\X:\\COM1");
    try testToPrefixedFileWithOracle("\\\\?\\X:/ABC/DEF. .", "\\??\\X:/ABC/DEF. .");
    try testToPrefixedFileWithOracle("\\\\?\\X:\\ABC\\..\\..\\..", "\\??\\X:\\ABC\\..\\..\\..");
    // NT Namespace
    // Fully unmodified
    try testToPrefixedFileWithOracle("\\??\\X:", "\\??\\X:");
    try testToPrefixedFileWithOracle("\\??\\X:\\COM1", "\\??\\X:\\COM1");
    try testToPrefixedFileWithOracle("\\??\\X:/ABC/DEF. .", "\\??\\X:/ABC/DEF. .");
    try testToPrefixedFileWithOracle("\\??\\X:\\ABC\\..\\..\\..", "\\??\\X:\\ABC\\..\\..\\..");

    // 'Fake' Verbatim
    // If the prefix looks like the verbatim prefix but not all path separators in the
    // prefix are backslashes, then it gets canonicalized and the prefix is dropped in favor
    // of the NT prefix.
    try testToPrefixedFileWithOracle("//?/C:/ABC", "\\??\\C:\\ABC");
    // 'Fake' NT
    // If the prefix looks like the NT prefix but not all path separators in the prefix
    // are backslashes, then it gets canonicalized and the /??/ is not dropped but
    // rather treated as part of the path. In other words, the path is treated
    // as a rooted path, so the final path is resolved relative to the CWD's
    // drive letter.
    // The -> shows an example of the result if the CWD's drive letter was X
    try testToPrefixedFileOnlyOracle("/??/C:/ABC"); // -> \??\X:\??\C:\ABC

    // Root Local Device
    // \\. and \\? always get converted to \??\
    try testToPrefixedFileWithOracle("\\\\.", "\\??\\");
    try testToPrefixedFileWithOracle("\\\\?", "\\??\\");
    try testToPrefixedFileWithOracle("//?", "\\??\\");
    try testToPrefixedFileWithOracle("//.", "\\??\\");
}

fn testRemoveDotDirs(str: []const u8, expected: []const u8) !void {
    const mutable = try testing.allocator.dupe(u8, str);
    defer testing.allocator.free(mutable);
    const actual = mutable[0..try windows.removeDotDirsSanitized(u8, mutable)];
    try testing.expect(std.mem.eql(u8, actual, expected));
}
fn testRemoveDotDirsError(err: anyerror, str: []const u8) !void {
    const mutable = try testing.allocator.dupe(u8, str);
    defer testing.allocator.free(mutable);
    try testing.expectError(err, windows.removeDotDirsSanitized(u8, mutable));
}
test "removeDotDirs" {
    try testRemoveDotDirs("", "");
    try testRemoveDotDirs(".", "");
    try testRemoveDotDirs(".\\", "");
    try testRemoveDotDirs(".\\.", "");
    try testRemoveDotDirs(".\\.\\", "");
    try testRemoveDotDirs(".\\.\\.", "");

    try testRemoveDotDirs("a", "a");
    try testRemoveDotDirs("a\\", "a\\");
    try testRemoveDotDirs("a\\b", "a\\b");
    try testRemoveDotDirs("a\\.", "a\\");
    try testRemoveDotDirs("a\\b\\.", "a\\b\\");
    try testRemoveDotDirs("a\\.\\b", "a\\b");

    try testRemoveDotDirs(".a", ".a");
    try testRemoveDotDirs(".a\\", ".a\\");
    try testRemoveDotDirs(".a\\.b", ".a\\.b");
    try testRemoveDotDirs(".a\\.", ".a\\");
    try testRemoveDotDirs(".a\\.\\.", ".a\\");
    try testRemoveDotDirs(".a\\.\\.\\.b", ".a\\.b");
    try testRemoveDotDirs(".a\\.\\.\\.b\\", ".a\\.b\\");

    try testRemoveDotDirsError(error.TooManyParentDirs, "..");
    try testRemoveDotDirsError(error.TooManyParentDirs, "..\\");
    try testRemoveDotDirsError(error.TooManyParentDirs, ".\\..\\");
    try testRemoveDotDirsError(error.TooManyParentDirs, ".\\.\\..\\");

    try testRemoveDotDirs("a\\..", "");
    try testRemoveDotDirs("a\\..\\", "");
    try testRemoveDotDirs("a\\..\\.", "");
    try testRemoveDotDirs("a\\..\\.\\", "");
    try testRemoveDotDirs("a\\..\\.\\.", "");
    try testRemoveDotDirsError(error.TooManyParentDirs, "a\\..\\.\\.\\..");

    try testRemoveDotDirs("a\\..\\.\\.\\b", "b");
    try testRemoveDotDirs("a\\..\\.\\.\\b\\", "b\\");
    try testRemoveDotDirs("a\\..\\.\\.\\b\\.", "b\\");
    try testRemoveDotDirs("a\\..\\.\\.\\b\\.\\", "b\\");
    try testRemoveDotDirs("a\\..\\.\\.\\b\\.\\..", "");
    try testRemoveDotDirs("a\\..\\.\\.\\b\\.\\..\\", "");
    try testRemoveDotDirs("a\\..\\.\\.\\b\\.\\..\\.", "");
    try testRemoveDotDirsError(error.TooManyParentDirs, "a\\..\\.\\.\\b\\.\\..\\.\\..");

    try testRemoveDotDirs("a\\b\\..\\", "a\\");
    try testRemoveDotDirs("a\\b\\..\\c", "a\\c");
}

const RTL_PATH_TYPE = enum(c_int) {
    Unknown,
    UncAbsolute,
    DriveAbsolute,
    DriveRelative,
    Rooted,
    Relative,
    LocalDevice,
    RootLocalDevice,
};

pub extern "ntdll" fn RtlDetermineDosPathNameType_U(
    Path: [*:0]const u16,
) callconv(.winapi) RTL_PATH_TYPE;

test "getWin32PathType vs RtlDetermineDosPathNameType_U" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var buf: std.ArrayList(u16) = .empty;
    defer buf.deinit(std.testing.allocator);

    var wtf8_buf: std.ArrayList(u8) = .empty;
    defer wtf8_buf.deinit(std.testing.allocator);

    var random = std.Random.DefaultPrng.init(std.testing.random_seed);
    const rand = random.random();

    for (0..1000) |_| {
        buf.clearRetainingCapacity();
        const path = try getRandomWtf16Path(std.testing.allocator, &buf, rand);
        wtf8_buf.clearRetainingCapacity();
        const wtf8_len = std.unicode.calcWtf8Len(path);
        try wtf8_buf.ensureTotalCapacity(std.testing.allocator, wtf8_len);
        wtf8_buf.items.len = wtf8_len;
        std.debug.assert(std.unicode.wtf16LeToWtf8(wtf8_buf.items, path) == wtf8_len);

        const windows_type = RtlDetermineDosPathNameType_U(path);
        const wtf16_type = std.fs.path.getWin32PathType(u16, path);
        const wtf8_type = std.fs.path.getWin32PathType(u8, wtf8_buf.items);

        checkPathType(windows_type, wtf16_type) catch |err| {
            std.debug.print("expected type {}, got {} for path: {f}\n", .{ windows_type, wtf16_type, std.unicode.fmtUtf16Le(path) });
            std.debug.print("path bytes:\n", .{});
            std.debug.dumpHex(std.mem.sliceAsBytes(path));
            return err;
        };

        if (wtf16_type != wtf8_type) {
            std.debug.print("type mismatch between wtf8: {} and wtf16: {} for path: {f}\n", .{ wtf8_type, wtf16_type, std.unicode.fmtUtf16Le(path) });
            std.debug.print("wtf-16 path bytes:\n", .{});
            std.debug.dumpHex(std.mem.sliceAsBytes(path));
            std.debug.print("wtf-8 path bytes:\n", .{});
            std.debug.dumpHex(std.mem.sliceAsBytes(wtf8_buf.items));
            return error.Wtf8Wtf16Mismatch;
        }
    }
}

fn checkPathType(windows_type: RTL_PATH_TYPE, zig_type: std.fs.path.Win32PathType) !void {
    const expected_windows_type: RTL_PATH_TYPE = switch (zig_type) {
        .unc_absolute => .UncAbsolute,
        .drive_absolute => .DriveAbsolute,
        .drive_relative => .DriveRelative,
        .rooted => .Rooted,
        .relative => .Relative,
        .local_device => .LocalDevice,
        .root_local_device => .RootLocalDevice,
    };
    if (windows_type != expected_windows_type) return error.PathTypeMismatch;
}

fn getRandomWtf16Path(allocator: std.mem.Allocator, buf: *std.ArrayList(u16), rand: std.Random) ![:0]const u16 {
    const Choice = enum {
        backslash,
        slash,
        control,
        printable,
        non_ascii,
    };

    const choices = rand.uintAtMostBiased(u16, 32);

    for (0..choices) |_| {
        const choice = rand.enumValue(Choice);
        const code_unit = switch (choice) {
            .backslash => '\\',
            .slash => '/',
            .control => switch (rand.uintAtMostBiased(u8, 0x20)) {
                0x20 => '\x7F',
                else => |b| b + 1, // no NUL
            },
            .printable => '!' + rand.uintAtMostBiased(u8, '~' - '!'),
            .non_ascii => rand.intRangeAtMostBiased(u16, 0x80, 0xFFFF),
        };
        try buf.append(allocator, std.mem.nativeToLittle(u16, code_unit));
    }

    try buf.append(allocator, 0);
    return buf.items[0 .. buf.items.len - 1 :0];
}
