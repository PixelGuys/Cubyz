const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("../std.zig");
const Io = std.Io;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const wasi = std.os.wasi;
const windows = std.os.windows;
const ArenaAllocator = std.heap.ArenaAllocator;
const Dir = std.Io.Dir;
const File = std.Io.File;
const SymLinkFlags = std.Io.Dir.SymLinkFlags;

const testing = std.testing;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const tmpDir = std.testing.tmpDir;

// This is kept in sync with Io.Threaded.realPath .
pub inline fn isRealPathSupported() bool {
    return switch (native_os) {
        .windows,
        .driverkit,
        .ios,
        .maccatalyst,
        .macos,
        .tvos,
        .visionos,
        .watchos,
        .linux,
        .serenity,
        .illumos,
        .freebsd,
        => true,
        .dragonfly => builtin.os.version_range.semver.min.order(.{ .major = 6, .minor = 0, .patch = 0 }) != .lt,
        else => false,
    };
}

const PathType = enum {
    relative,
    absolute,
    unc,

    fn isSupported(self: PathType, target_os: std.Target.Os) bool {
        return switch (self) {
            .relative => true,
            .absolute => isRealPathSupported(),
            .unc => target_os.tag == .windows,
        };
    }

    const TransformError = Dir.RealPathError || error{OutOfMemory};
    const TransformFn = fn (Allocator, Io, Dir, relative_path: [:0]const u8) TransformError![:0]const u8;

    fn getTransformFn(comptime path_type: PathType) TransformFn {
        switch (path_type) {
            .relative => return struct {
                fn transform(allocator: Allocator, io: Io, dir: Dir, relative_path: [:0]const u8) TransformError![:0]const u8 {
                    _ = allocator;
                    _ = io;
                    _ = dir;
                    return relative_path;
                }
            }.transform,
            .absolute => return struct {
                fn transform(allocator: Allocator, io: Io, dir: Dir, relative_path: [:0]const u8) TransformError![:0]const u8 {
                    // The final path may not actually exist which would cause realpath to fail.
                    // So instead, we get the path of the dir and join it with the relative path.
                    var fd_path_buf: [Dir.max_path_bytes]u8 = undefined;
                    const dir_path = fd_path_buf[0..try dir.realPath(io, &fd_path_buf)];
                    return Dir.path.joinZ(allocator, &.{ dir_path, relative_path });
                }
            }.transform,
            .unc => return struct {
                fn transform(allocator: Allocator, io: Io, dir: Dir, relative_path: [:0]const u8) TransformError![:0]const u8 {
                    // Any drive absolute path (C:\foo) can be converted into a UNC path by
                    // using '127.0.0.1' as the server name and '<drive letter>$' as the share name.
                    var fd_path_buf: [Dir.max_path_bytes]u8 = undefined;
                    const dir_path = fd_path_buf[0..try dir.realPath(io, &fd_path_buf)];
                    const windows_path_type = Dir.path.getWin32PathType(u8, dir_path);
                    switch (windows_path_type) {
                        .unc_absolute => return Dir.path.joinZ(allocator, &.{ dir_path, relative_path }),
                        .drive_absolute => {
                            // `C:\<...>` -> `\\127.0.0.1\C$\<...>`
                            const prepended = "\\\\127.0.0.1\\";
                            var path = try Dir.path.joinZ(allocator, &.{ prepended, dir_path, relative_path });
                            path[prepended.len + 1] = '$';
                            return path;
                        },
                        else => unreachable,
                    }
                }
            }.transform,
        }
    }
};

const TestContext = struct {
    io: Io,
    path_type: PathType,
    path_sep: u8,
    arena: ArenaAllocator,
    tmp: testing.TmpDir,
    dir: Dir,
    transform_fn: *const PathType.TransformFn,

    pub fn init(path_type: PathType, path_sep: u8, allocator: Allocator, transform_fn: *const PathType.TransformFn) TestContext {
        const tmp = tmpDir(.{ .iterate = true });
        return .{
            .io = testing.io,
            .path_type = path_type,
            .path_sep = path_sep,
            .arena = ArenaAllocator.init(allocator),
            .tmp = tmp,
            .dir = tmp.dir,
            .transform_fn = transform_fn,
        };
    }

    pub fn deinit(self: *TestContext) void {
        self.arena.deinit();
        self.tmp.cleanup();
    }

    /// Returns the `relative_path` transformed into the TestContext's `path_type`,
    /// with any supported path separators replaced by `path_sep`.
    /// The result is allocated by the TestContext's arena and will be free'd during
    /// `TestContext.deinit`.
    pub fn transformPath(self: *TestContext, relative_path: [:0]const u8) ![:0]const u8 {
        const allocator = self.arena.allocator();
        const transformed_path = try self.transform_fn(allocator, self.io, self.dir, relative_path);
        if (native_os == .windows) {
            const transformed_sep_path = try allocator.dupeZ(u8, transformed_path);
            std.mem.replaceScalar(u8, transformed_sep_path, switch (self.path_sep) {
                '/' => '\\',
                '\\' => '/',
                else => unreachable,
            }, self.path_sep);
            return transformed_sep_path;
        }
        return transformed_path;
    }

    /// Replaces any path separators with the canonical path separator for the platform
    /// (e.g. all path separators are converted to `\` on Windows).
    /// If path separators are replaced, then the result is allocated by the
    /// TestContext's arena and will be free'd during `TestContext.deinit`.
    pub fn toCanonicalPathSep(self: *TestContext, path: [:0]const u8) ![:0]const u8 {
        if (native_os == .windows) {
            const allocator = self.arena.allocator();
            const transformed_sep_path = try allocator.dupeZ(u8, path);
            std.mem.replaceScalar(u8, transformed_sep_path, '/', '\\');
            return transformed_sep_path;
        }
        return path;
    }
};

/// `test_func` must be a function that takes a `*TestContext` as a parameter and returns `!void`.
/// `test_func` will be called once for each PathType that the current target supports,
/// and will be passed a TestContext that can transform a relative path into the path type under test.
/// The TestContext will also create a tmp directory for you (and will clean it up for you too).
fn testWithAllSupportedPathTypes(test_func: anytype) !void {
    try testWithPathTypeIfSupported(.relative, '/', test_func);
    try testWithPathTypeIfSupported(.absolute, '/', test_func);
    try testWithPathTypeIfSupported(.unc, '/', test_func);
    try testWithPathTypeIfSupported(.relative, '\\', test_func);
    try testWithPathTypeIfSupported(.absolute, '\\', test_func);
    try testWithPathTypeIfSupported(.unc, '\\', test_func);
}

fn testWithPathTypeIfSupported(comptime path_type: PathType, comptime path_sep: u8, test_func: anytype) !void {
    if (!(comptime path_type.isSupported(builtin.os))) return;
    if (!(comptime Dir.path.isSep(path_sep))) return;

    var ctx = TestContext.init(path_type, path_sep, testing.allocator, path_type.getTransformFn());
    defer ctx.deinit();

    try test_func(&ctx);
}

// For use in test setup.  If the symlink creation fails on Windows with
// AccessDenied/PermissionDenied/FileSystem, then make the test failure silent (it is not a Zig failure).
fn setupSymlink(io: Io, dir: Dir, target: []const u8, link: []const u8, flags: SymLinkFlags) !void {
    return dir.symLink(io, target, link, flags) catch |err| switch (err) {
        // On Windows, symlinks require admin privileges and the underlying filesystem must support symlinks
        error.AccessDenied, error.PermissionDenied, error.FileSystem => if (native_os == .windows) return error.SkipZigTest else return err,
        else => return err,
    };
}

// For use in test setup.  If the symlink creation fails on Windows with
// AccessDeniedPermissionDenied/FileSystem, then make the test failure silent (it is not a Zig failure).
fn setupSymlinkAbsolute(io: Io, target: []const u8, link: []const u8, flags: SymLinkFlags) !void {
    return Dir.symLinkAbsolute(io, target, link, flags) catch |err| switch (err) {
        // On Windows, symlinks require admin privileges and the underlying filesystem must support symlinks
        error.AccessDenied, error.PermissionDenied, error.FileSystem => if (native_os == .windows) return error.SkipZigTest else return err,
        else => return err,
    };
}

test "Dir.readLink" {
    const io = testing.io;

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            // Create some targets
            const file_target_path = try ctx.transformPath("file.txt");
            try ctx.dir.writeFile(io, .{ .sub_path = file_target_path, .data = "nonsense" });
            const dir_target_path = try ctx.transformPath("subdir");
            try ctx.dir.createDir(io, dir_target_path, .default_dir);

            // On Windows, symlink targets always use the canonical path separator
            const canonical_file_target_path = try ctx.toCanonicalPathSep(file_target_path);
            const canonical_dir_target_path = try ctx.toCanonicalPathSep(dir_target_path);

            // test 1: symlink to a file
            try setupSymlink(io, ctx.dir, file_target_path, "symlink1", .{});
            try testReadLink(io, ctx.dir, canonical_file_target_path, "symlink1");

            // test 2: symlink to a directory (can be different on Windows)
            try setupSymlink(io, ctx.dir, dir_target_path, "symlink2", .{ .is_directory = true });
            try testReadLink(io, ctx.dir, canonical_dir_target_path, "symlink2");

            // test 3: relative path symlink
            const parent_file = ".." ++ Dir.path.sep_str ++ "target.txt";
            const canonical_parent_file = try ctx.toCanonicalPathSep(parent_file);
            var subdir = try ctx.dir.createDirPathOpen(io, "subdir", .{});
            defer subdir.close(io);
            try setupSymlink(io, subdir, canonical_parent_file, "relative-link.txt", .{});
            try testReadLink(io, subdir, canonical_parent_file, "relative-link.txt");
        }
    }.impl);
}

test "Dir.readLink on non-symlinks" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const file_path = try ctx.transformPath("file.txt");
            try ctx.dir.writeFile(io, .{ .sub_path = file_path, .data = "nonsense" });
            const dir_path = try ctx.transformPath("subdir");
            try ctx.dir.createDir(io, dir_path, .default_dir);

            // file
            var buffer: [Dir.max_path_bytes]u8 = undefined;
            try std.testing.expectError(error.NotLink, ctx.dir.readLink(io, file_path, &buffer));

            // dir
            try std.testing.expectError(error.NotLink, ctx.dir.readLink(io, dir_path, &buffer));
        }
    }.impl);
}

fn testReadLink(io: Io, dir: Dir, target_path: []const u8, symlink_path: []const u8) !void {
    var buffer: [Dir.max_path_bytes]u8 = undefined;
    const actual = buffer[0..try dir.readLink(io, symlink_path, &buffer)];
    try expectEqualStrings(target_path, actual);
}

fn testReadLinkAbsolute(io: Io, target_path: []const u8, symlink_path: []const u8) !void {
    var buffer: [Dir.max_path_bytes]u8 = undefined;
    const given = buffer[0..try Dir.readLinkAbsolute(io, symlink_path, &buffer)];
    try expectEqualStrings(target_path, given);
}

test "File.stat on a File that is a symlink returns Kind.sym_link" {
    const io = testing.io;

    // This test requires getting a file descriptor of a symlink which is not
    // possible on all targets.
    switch (builtin.target.os.tag) {
        .windows, .linux => {},
        else => return error.SkipZigTest,
    }

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const dir_target_path = try ctx.transformPath("subdir");
            try ctx.dir.createDir(io, dir_target_path, .default_dir);

            try setupSymlink(io, ctx.dir, dir_target_path, "symlink", .{ .is_directory = true });

            var symlink: File = try ctx.dir.openFile(io, "symlink", .{
                .follow_symlinks = false,
                .path_only = true,
            });
            defer symlink.close(io);

            const stat = try symlink.stat(io);
            try expectEqual(File.Kind.sym_link, stat.kind);
        }
    }.impl);
}

test "Dir.statFile on a symlink" {
    const io = testing.io;

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const dir_target_path = try ctx.transformPath("test_file");
            try ctx.dir.writeFile(io, .{
                .sub_path = dir_target_path,
                .data = "Some test content",
            });

            try setupSymlink(io, ctx.dir, dir_target_path, "symlink", .{});

            const file_stat = try ctx.dir.statFile(io, "test_file", .{ .follow_symlinks = false });
            try testing.expectEqual(File.Kind.file, file_stat.kind);

            const link_stat = try ctx.dir.statFile(io, "symlink", .{ .follow_symlinks = false });
            try testing.expectEqual(File.Kind.sym_link, link_stat.kind);
        }
    }.impl);
}

test "openDir" {
    const io = testing.io;

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const allocator = ctx.arena.allocator();
            const subdir_path = try ctx.transformPath("subdir");
            try ctx.dir.createDir(io, subdir_path, .default_dir);

            for ([_][]const u8{ "", ".", ".." }) |sub_path| {
                const dir_path = try Dir.path.join(allocator, &.{ subdir_path, sub_path });
                var dir = try ctx.dir.openDir(io, dir_path, .{});
                defer dir.close(io);
            }
        }
    }.impl);
}

test "accessAbsolute" {
    if (!isRealPathSupported()) return error.SkipZigTest;

    const io = testing.io;
    const gpa = testing.allocator;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const base_path = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(base_path);

    try Dir.accessAbsolute(io, base_path, .{});
}

test "openDirAbsolute" {
    if (!isRealPathSupported()) return error.SkipZigTest;

    const io = testing.io;
    const gpa = testing.allocator;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const tmp_ino = (try tmp.dir.stat(io)).inode;

    try tmp.dir.createDir(io, "subdir", .default_dir);
    const sub_path = try tmp.dir.realPathFileAlloc(io, "subdir", gpa);
    defer gpa.free(sub_path);

    // Can open sub_path
    var tmp_sub = try Dir.openDirAbsolute(io, sub_path, .{});
    defer tmp_sub.close(io);

    const sub_ino = (try tmp_sub.stat(io)).inode;

    {
        // Can open sub_path + ".."
        const dir_path = try Dir.path.join(testing.allocator, &.{ sub_path, ".." });
        defer testing.allocator.free(dir_path);

        var dir = try Dir.openDirAbsolute(io, dir_path, .{});
        defer dir.close(io);

        const ino = (try dir.stat(io)).inode;
        try expectEqual(tmp_ino, ino);
    }

    {
        // Can open sub_path + "."
        const dir_path = try Dir.path.join(testing.allocator, &.{ sub_path, "." });
        defer testing.allocator.free(dir_path);

        var dir = try Dir.openDirAbsolute(io, dir_path, .{});
        defer dir.close(io);

        const ino = (try dir.stat(io)).inode;
        try expectEqual(sub_ino, ino);
    }

    {
        // Can open subdir + "..", with some extra "."
        const dir_path = try Dir.path.join(testing.allocator, &.{ sub_path, ".", "..", "." });
        defer testing.allocator.free(dir_path);

        var dir = try Dir.openDirAbsolute(io, dir_path, .{});
        defer dir.close(io);

        const ino = (try dir.stat(io)).inode;
        try expectEqual(tmp_ino, ino);
    }
}

test "openDir cwd parent '..'" {
    const io = testing.io;

    var dir = Dir.cwd().openDir(io, "..", .{}) catch |err| {
        if (native_os == .wasi and err == error.PermissionDenied) {
            return; // This is okay. WASI disallows escaping from the fs sandbox
        }
        return err;
    };
    defer dir.close(io);
}

test "openDir non-cwd parent '..'" {
    switch (native_os) {
        .wasi, .netbsd, .openbsd => return error.SkipZigTest,
        else => {},
    }

    const io = testing.io;
    const gpa = testing.allocator;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var subdir = try tmp.dir.createDirPathOpen(io, "subdir", .{});
    defer subdir.close(io);

    var dir = try subdir.openDir(io, "..", .{});
    defer dir.close(io);

    const expected_path = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(expected_path);

    const actual_path = try dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(actual_path);

    try expectEqualStrings(expected_path, actual_path);
}

test "readLinkAbsolute" {
    if (!isRealPathSupported()) return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    // Create some targets
    try tmp.dir.writeFile(io, .{ .sub_path = "file.txt", .data = "nonsense" });
    try tmp.dir.createDir(io, "subdir", .default_dir);

    // Get base abs path
    var arena_allocator = ArenaAllocator.init(testing.allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const base_path = try tmp.dir.realPathFileAlloc(io, ".", arena);

    {
        const target_path = try Dir.path.join(arena, &.{ base_path, "file.txt" });
        const symlink_path = try Dir.path.join(arena, &.{ base_path, "symlink1" });

        // Create symbolic link by path
        try setupSymlinkAbsolute(io, target_path, symlink_path, .{});
        try testReadLinkAbsolute(io, target_path, symlink_path);
    }
    {
        const target_path = try Dir.path.join(arena, &.{ base_path, "subdir" });
        const symlink_path = try Dir.path.join(arena, &.{ base_path, "symlink2" });

        // Create symbolic link to a directory by path
        try setupSymlinkAbsolute(io, target_path, symlink_path, .{ .is_directory = true });
        try testReadLinkAbsolute(io, target_path, symlink_path);
    }
}

test "Dir.Iterator" {
    const io = testing.io;

    var tmp_dir = tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    // First, create a couple of entries to iterate over.
    const file = try tmp_dir.dir.createFile(io, "some_file", .{});
    file.close(io);

    try tmp_dir.dir.createDir(io, "some_dir", .default_dir);

    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var entries = std.array_list.Managed(Dir.Entry).init(allocator);

    // Create iterator.
    var iter = tmp_dir.dir.iterate();
    while (try iter.next(io)) |entry| {
        // We cannot just store `entry` as on Windows, we're re-using the name buffer
        // which means we'll actually share the `name` pointer between entries!
        const name = try allocator.dupe(u8, entry.name);
        try entries.append(Dir.Entry{ .name = name, .kind = entry.kind, .inode = 0 });
    }

    try expectEqual(@as(usize, 2), entries.items.len); // note that the Iterator skips '.' and '..'
    try expect(contains(&entries, .{ .name = "some_file", .kind = .file, .inode = 0 }));
    try expect(contains(&entries, .{ .name = "some_dir", .kind = .directory, .inode = 0 }));
}

test "Dir.Iterator many entries" {
    const io = testing.io;

    var tmp_dir = tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    const num = 1024;
    var i: usize = 0;
    var buf: [4]u8 = undefined; // Enough to store "1024".
    while (i < num) : (i += 1) {
        const name = try std.fmt.bufPrint(&buf, "{}", .{i});
        const file = try tmp_dir.dir.createFile(io, name, .{});
        file.close(io);
    }

    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var entries = std.array_list.Managed(Dir.Entry).init(allocator);

    // Create iterator.
    var iter = tmp_dir.dir.iterate();
    while (try iter.next(io)) |entry| {
        // We cannot just store `entry` as on Windows, we're re-using the name buffer
        // which means we'll actually share the `name` pointer between entries!
        const name = try allocator.dupe(u8, entry.name);
        try entries.append(.{ .name = name, .kind = entry.kind, .inode = 0 });
    }

    i = 0;
    while (i < num) : (i += 1) {
        const name = try std.fmt.bufPrint(&buf, "{}", .{i});
        try expect(contains(&entries, .{ .name = name, .kind = .file, .inode = 0 }));
    }
}

test "Dir.Iterator twice" {
    const io = testing.io;

    var tmp_dir = tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    // First, create a couple of entries to iterate over.
    const file = try tmp_dir.dir.createFile(io, "some_file", .{});
    file.close(io);

    try tmp_dir.dir.createDir(io, "some_dir", .default_dir);

    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var i: u8 = 0;
    while (i < 2) : (i += 1) {
        var entries = std.array_list.Managed(Dir.Entry).init(allocator);

        // Create iterator.
        var iter = tmp_dir.dir.iterate();
        while (try iter.next(io)) |entry| {
            // We cannot just store `entry` as on Windows, we're re-using the name buffer
            // which means we'll actually share the `name` pointer between entries!
            const name = try allocator.dupe(u8, entry.name);
            try entries.append(Dir.Entry{ .name = name, .kind = entry.kind, .inode = 0 });
        }

        try expectEqual(@as(usize, 2), entries.items.len); // note that the Iterator skips '.' and '..'
        try expect(contains(&entries, .{ .name = "some_file", .kind = .file, .inode = 0 }));
        try expect(contains(&entries, .{ .name = "some_dir", .kind = .directory, .inode = 0 }));
    }
}

test "Dir.Iterator reset" {
    const io = testing.io;

    var tmp_dir = tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    // First, create a couple of entries to iterate over.
    const file = try tmp_dir.dir.createFile(io, "some_file", .{});
    file.close(io);

    try tmp_dir.dir.createDir(io, "some_dir", .default_dir);

    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create iterator.
    var iter = tmp_dir.dir.iterate();

    var i: u8 = 0;
    while (i < 2) : (i += 1) {
        var entries = std.array_list.Managed(Dir.Entry).init(allocator);

        while (try iter.next(io)) |entry| {
            // We cannot just store `entry` as on Windows, we're re-using the name buffer
            // which means we'll actually share the `name` pointer between entries!
            const name = try allocator.dupe(u8, entry.name);
            try entries.append(.{ .name = name, .kind = entry.kind, .inode = 0 });
        }

        try expectEqual(@as(usize, 2), entries.items.len); // note that the Iterator skips '.' and '..'
        try expect(contains(&entries, .{ .name = "some_file", .kind = .file, .inode = 0 }));
        try expect(contains(&entries, .{ .name = "some_dir", .kind = .directory, .inode = 0 }));

        iter.reader.reset();
    }
}

test "Dir.Iterator but dir is deleted during iteration" {
    const io = testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create directory and setup an iterator for it
    var subdir = try tmp.dir.createDirPathOpen(io, "subdir", .{ .open_options = .{ .iterate = true } });
    defer subdir.close(io);

    var iterator = subdir.iterate();

    // Create something to iterate over within the subdir
    try tmp.dir.createDirPath(io, "subdir" ++ Dir.path.sep_str ++ "b");

    // Then, before iterating, delete the directory that we're iterating.
    // This is a contrived reproduction, but this could happen outside of the program, in another thread, etc.
    // If we get an error while trying to delete, we can skip this test (this will happen on platforms
    // like Windows which will give FileBusy if the directory is currently open for iteration).
    tmp.dir.deleteTree(io, "subdir") catch return error.SkipZigTest;

    // Now, when we try to iterate, the next call should return null immediately.
    const entry = try iterator.next(io);
    try testing.expect(entry == null);
}

fn entryEql(lhs: Dir.Entry, rhs: Dir.Entry) bool {
    return mem.eql(u8, lhs.name, rhs.name) and lhs.kind == rhs.kind;
}

fn contains(entries: *const std.array_list.Managed(Dir.Entry), el: Dir.Entry) bool {
    for (entries.items) |entry| {
        if (entryEql(entry, el)) return true;
    }
    return false;
}

test "Dir.realPath smoke test" {
    if (!isRealPathSupported()) return error.SkipZigTest;

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const arena = ctx.arena.allocator();
            const test_file_path = try ctx.transformPath("test_file");
            const test_dir_path = try ctx.transformPath("test_dir");
            var buf: [Dir.max_path_bytes]u8 = undefined;

            // FileNotFound if the path doesn't exist
            try expectError(error.FileNotFound, ctx.dir.realPathFileAlloc(io, test_file_path, arena));
            try expectError(error.FileNotFound, ctx.dir.realPathFile(io, test_file_path, &buf));
            try expectError(error.FileNotFound, ctx.dir.realPathFileAlloc(io, test_dir_path, arena));
            try expectError(error.FileNotFound, ctx.dir.realPathFile(io, test_dir_path, &buf));

            // Now create the file and dir
            try ctx.dir.writeFile(io, .{ .sub_path = test_file_path, .data = "" });
            try ctx.dir.createDir(io, test_dir_path, .default_dir);

            const base_path = try ctx.transformPath(".");
            const base_realpath = try ctx.dir.realPathFileAlloc(io, base_path, arena);
            const expected_file_path = try Dir.path.join(arena, &.{ base_realpath, "test_file" });
            const expected_dir_path = try Dir.path.join(arena, &.{ base_realpath, "test_dir" });

            // First, test non-alloc version
            {
                const file_path = buf[0..try ctx.dir.realPathFile(io, test_file_path, &buf)];
                try expectEqualStrings(expected_file_path, file_path);

                const dir_path = buf[0..try ctx.dir.realPathFile(io, test_dir_path, &buf)];
                try expectEqualStrings(expected_dir_path, dir_path);
            }

            // Next, test alloc version
            {
                const file_path = try ctx.dir.realPathFileAlloc(io, test_file_path, arena);
                try expectEqualStrings(expected_file_path, file_path);

                const dir_path = try ctx.dir.realPathFileAlloc(io, test_dir_path, arena);
                try expectEqualStrings(expected_dir_path, dir_path);
            }
        }
    }.impl);
}

test "readFileAlloc" {
    const io = testing.io;

    var tmp_dir = tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile(io, "test_file", .{ .read = true });
    defer file.close(io);

    const buf1 = try tmp_dir.dir.readFileAlloc(io, "test_file", testing.allocator, .limited(1024));
    defer testing.allocator.free(buf1);
    try expectEqualStrings("", buf1);

    const write_buf: []const u8 = "this is a test.\nthis is a test.\nthis is a test.\nthis is a test.\n";
    try file.writeStreamingAll(io, write_buf);

    {
        // max_bytes > file_size
        const buf2 = try tmp_dir.dir.readFileAlloc(io, "test_file", testing.allocator, .limited(1024));
        defer testing.allocator.free(buf2);
        try expectEqualStrings(write_buf, buf2);
    }

    {
        // max_bytes == file_size
        try expectError(
            error.StreamTooLong,
            tmp_dir.dir.readFileAlloc(io, "test_file", testing.allocator, .limited(write_buf.len)),
        );
    }

    {
        // max_bytes == file_size + 1
        const buf2 = try tmp_dir.dir.readFileAlloc(io, "test_file", testing.allocator, .limited(write_buf.len + 1));
        defer testing.allocator.free(buf2);
        try expectEqualStrings(write_buf, buf2);
    }

    // max_bytes < file_size
    try expectError(
        error.StreamTooLong,
        tmp_dir.dir.readFileAlloc(io, "test_file", testing.allocator, .limited(write_buf.len - 1)),
    );
}

test "Dir.statFile" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            {
                const test_file_name = try ctx.transformPath("test_file");

                try expectError(error.FileNotFound, ctx.dir.statFile(io, test_file_name, .{}));

                try ctx.dir.writeFile(io, .{ .sub_path = test_file_name, .data = "" });

                const stat = try ctx.dir.statFile(io, test_file_name, .{});
                try expectEqual(.file, stat.kind);
            }
            {
                const test_dir_name = try ctx.transformPath("test_dir");

                try expectError(error.FileNotFound, ctx.dir.statFile(io, test_dir_name, .{}));

                try ctx.dir.createDir(io, test_dir_name, .default_dir);

                const stat = try ctx.dir.statFile(io, test_dir_name, .{});
                try expectEqual(.directory, stat.kind);
            }
        }
    }.impl);
}

test "statFile on dangling symlink" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const symlink_name = try ctx.transformPath("dangling-symlink");
            const symlink_target = "." ++ Dir.path.sep_str ++ "doesnotexist";

            try setupSymlink(io, ctx.dir, symlink_target, symlink_name, .{});

            try expectError(error.FileNotFound, ctx.dir.statFile(io, symlink_name, .{}));
        }
    }.impl);
}

test "directory operations on files" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;

            const test_file_name = try ctx.transformPath("test_file");

            var file = try ctx.dir.createFile(io, test_file_name, .{ .read = true });
            file.close(io);

            try expectError(error.PathAlreadyExists, ctx.dir.createDir(io, test_file_name, .default_dir));
            try expectError(error.NotDir, ctx.dir.openDir(io, test_file_name, .{}));
            try expectError(error.NotDir, ctx.dir.deleteDir(io, test_file_name));

            if (ctx.path_type == .absolute and comptime PathType.absolute.isSupported(builtin.os)) {
                try expectError(error.PathAlreadyExists, Dir.createDirAbsolute(io, test_file_name, .default_dir));
                try expectError(error.NotDir, Dir.deleteDirAbsolute(io, test_file_name));
            }

            // ensure the file still exists and is a file as a sanity check
            file = try ctx.dir.openFile(io, test_file_name, .{});
            const stat = try file.stat(io);
            try expectEqual(File.Kind.file, stat.kind);
            file.close(io);
        }
    }.impl);
}

test "file operations on directories" {
    // TODO: fix this test on FreeBSD. https://github.com/ziglang/zig/issues/1759
    if (native_os == .freebsd) return error.SkipZigTest;

    const io = testing.io;

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const test_dir_name = try ctx.transformPath("test_dir");

            try ctx.dir.createDir(io, test_dir_name, .default_dir);

            try expectError(error.IsDir, ctx.dir.createFile(io, test_dir_name, .{}));
            try expectError(error.IsDir, ctx.dir.deleteFile(io, test_dir_name));
            switch (native_os) {
                .netbsd => {
                    // no error when reading a directory. See https://github.com/ziglang/zig/issues/5732
                    const buf = try ctx.dir.readFileAlloc(io, test_dir_name, testing.allocator, .unlimited);
                    testing.allocator.free(buf);
                },
                else => {
                    try expectError(error.IsDir, ctx.dir.readFileAlloc(io, test_dir_name, testing.allocator, .unlimited));
                },
            }

            if (native_os == .wasi and builtin.link_libc) {
                // wasmtime unexpectedly succeeds here, see https://github.com/ziglang/zig/issues/20747
                const handle = try ctx.dir.openFile(io, test_dir_name, .{ .mode = .read_write });
                handle.close(io);
            } else {
                // Note: The `.mode = .read_write` is necessary to ensure the error occurs on all platforms.
                try expectError(error.IsDir, ctx.dir.openFile(io, test_dir_name, .{ .mode = .read_write }));
            }

            {
                const handle = try ctx.dir.openFile(io, test_dir_name, .{ .allow_directory = true, .mode = .read_only });
                defer handle.close(io);

                // Reading from the handle should fail
                if (native_os != .netbsd) {
                    var buf: [1]u8 = undefined;
                    try expectError(error.IsDir, handle.readStreaming(io, &.{&buf}));
                    try expectError(error.IsDir, handle.readPositional(io, &.{&buf}, 0));
                }
            }
            try expectError(error.IsDir, ctx.dir.openFile(io, test_dir_name, .{ .allow_directory = false, .mode = .read_only }));

            if (ctx.path_type == .absolute and comptime PathType.absolute.isSupported(builtin.os)) {
                try expectError(error.IsDir, Dir.createFileAbsolute(io, test_dir_name, .{}));
                try expectError(error.IsDir, Dir.deleteFileAbsolute(io, test_dir_name));
            }

            // ensure the directory still exists as a sanity check
            var dir = try ctx.dir.openDir(io, test_dir_name, .{});
            dir.close(io);
        }
    }.impl);
}

test "createDirPathOpen parent dirs do not exist" {
    const io = testing.io;

    var tmp_dir = tmpDir(.{});
    defer tmp_dir.cleanup();

    var dir = try tmp_dir.dir.createDirPathOpen(io, "root_dir/parent_dir/some_dir", .{});
    dir.close(io);

    // double check that the full directory structure was created
    var dir_verification = try tmp_dir.dir.openDir(io, "root_dir/parent_dir/some_dir", .{});
    dir_verification.close(io);
}

test "deleteDir" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const test_dir_path = try ctx.transformPath("test_dir");
            const test_file_path = try ctx.transformPath("test_dir" ++ Dir.path.sep_str ++ "test_file");

            // deleting a non-existent directory
            try expectError(error.FileNotFound, ctx.dir.deleteDir(io, test_dir_path));

            // deleting a non-empty directory
            try ctx.dir.createDir(io, test_dir_path, .default_dir);
            try ctx.dir.writeFile(io, .{ .sub_path = test_file_path, .data = "" });
            try expectError(error.DirNotEmpty, ctx.dir.deleteDir(io, test_dir_path));

            // deleting an empty directory
            try ctx.dir.deleteFile(io, test_file_path);
            try ctx.dir.deleteDir(io, test_dir_path);
        }
    }.impl);
}

test "Dir.rename files" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            // Rename on Windows can hit intermittent AccessDenied errors
            // when certain conditions are true about the host system.
            // For now, skip this test when the path type is UNC to avoid them.
            // See https://github.com/ziglang/zig/issues/17134
            if (ctx.path_type == .unc) return;

            const missing_file_path = try ctx.transformPath("missing_file_name");
            const something_else_path = try ctx.transformPath("something_else");

            try expectError(error.FileNotFound, ctx.dir.rename(missing_file_path, ctx.dir, something_else_path, io));

            // Renaming files
            const test_file_name = try ctx.transformPath("test_file");
            const renamed_test_file_name = try ctx.transformPath("test_file_renamed");
            var file = try ctx.dir.createFile(io, test_file_name, .{ .read = true });
            file.close(io);
            try ctx.dir.rename(test_file_name, ctx.dir, renamed_test_file_name, io);

            // Ensure the file was renamed
            try expectError(error.FileNotFound, ctx.dir.openFile(io, test_file_name, .{}));
            file = try ctx.dir.openFile(io, renamed_test_file_name, .{});
            file.close(io);

            // Rename to self succeeds
            try ctx.dir.rename(renamed_test_file_name, ctx.dir, renamed_test_file_name, io);

            // Rename to existing file succeeds
            const existing_file_path = try ctx.transformPath("existing_file");
            var existing_file = try ctx.dir.createFile(io, existing_file_path, .{ .read = true });
            existing_file.close(io);
            try ctx.dir.rename(renamed_test_file_name, ctx.dir, existing_file_path, io);

            try expectError(error.FileNotFound, ctx.dir.openFile(io, renamed_test_file_name, .{}));
            file = try ctx.dir.openFile(io, existing_file_path, .{});
            file.close(io);
        }
    }.impl);
}

test "Dir.rename directories" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;

            // Rename on Windows can hit intermittent AccessDenied errors
            // when certain conditions are true about the host system.
            // For now, skip this test when the path type is UNC to avoid them.
            // See https://github.com/ziglang/zig/issues/17134
            if (ctx.path_type == .unc) return;

            const test_dir_path = try ctx.transformPath("test_dir");
            const test_dir_renamed_path = try ctx.transformPath("test_dir_renamed");

            // Renaming directories
            try ctx.dir.createDir(io, test_dir_path, .default_dir);
            try ctx.dir.rename(test_dir_path, ctx.dir, test_dir_renamed_path, io);

            // Ensure the directory was renamed
            try expectError(error.FileNotFound, ctx.dir.openDir(io, test_dir_path, .{}));
            var dir = try ctx.dir.openDir(io, test_dir_renamed_path, .{});

            // Put a file in the directory
            var file = try dir.createFile(io, "test_file", .{ .read = true });
            file.close(io);
            dir.close(io);

            const test_dir_renamed_again_path = try ctx.transformPath("test_dir_renamed_again");
            try ctx.dir.rename(test_dir_renamed_path, ctx.dir, test_dir_renamed_again_path, io);

            // Ensure the directory was renamed and the file still exists in it
            try expectError(error.FileNotFound, ctx.dir.openDir(io, test_dir_renamed_path, .{}));
            dir = try ctx.dir.openDir(io, test_dir_renamed_again_path, .{});
            file = try dir.openFile(io, "test_file", .{});
            file.close(io);
            dir.close(io);
        }
    }.impl);
}

test "Dir.rename directory onto empty dir" {
    // TODO: Fix on Windows, see https://github.com/ziglang/zig/issues/6364
    if (native_os == .windows) return error.SkipZigTest;

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;

            const test_dir_path = try ctx.transformPath("test_dir");
            const target_dir_path = try ctx.transformPath("target_dir_path");

            try ctx.dir.createDir(io, test_dir_path, .default_dir);
            try ctx.dir.createDir(io, target_dir_path, .default_dir);
            try ctx.dir.rename(test_dir_path, ctx.dir, target_dir_path, io);

            // Ensure the directory was renamed
            try expectError(error.FileNotFound, ctx.dir.openDir(io, test_dir_path, .{}));
            var dir = try ctx.dir.openDir(io, target_dir_path, .{});
            dir.close(io);
        }
    }.impl);
}

test "Dir.rename directory onto non-empty dir" {
    // TODO: Fix on Windows, see https://github.com/ziglang/zig/issues/6364
    if (native_os == .windows) return error.SkipZigTest;

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const test_dir_path = try ctx.transformPath("test_dir");
            const target_dir_path = try ctx.transformPath("target_dir_path");

            try ctx.dir.createDir(io, test_dir_path, .default_dir);

            var target_dir = try ctx.dir.createDirPathOpen(io, target_dir_path, .{});
            var file = try target_dir.createFile(io, "test_file", .{ .read = true });
            file.close(io);
            target_dir.close(io);

            try expectError(error.DirNotEmpty, ctx.dir.rename(test_dir_path, ctx.dir, target_dir_path, io));

            // Ensure the directory was not renamed
            var dir = try ctx.dir.openDir(io, test_dir_path, .{});
            dir.close(io);
        }
    }.impl);
}

test "Dir.rename file <-> dir" {
    // TODO: Fix on Windows, see https://github.com/ziglang/zig/issues/6364
    if (native_os == .windows) return error.SkipZigTest;

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const test_file_path = try ctx.transformPath("test_file");
            const test_dir_path = try ctx.transformPath("test_dir");

            var file = try ctx.dir.createFile(io, test_file_path, .{ .read = true });
            file.close(io);
            try ctx.dir.createDir(io, test_dir_path, .default_dir);
            try expectError(error.IsDir, ctx.dir.rename(test_file_path, ctx.dir, test_dir_path, io));
            try expectError(error.NotDir, ctx.dir.rename(test_dir_path, ctx.dir, test_file_path, io));
        }
    }.impl);
}

test "rename" {
    const io = testing.io;

    var tmp_dir1 = tmpDir(.{});
    defer tmp_dir1.cleanup();

    var tmp_dir2 = tmpDir(.{});
    defer tmp_dir2.cleanup();

    // Renaming files
    const test_file_name = "test_file";
    const renamed_test_file_name = "test_file_renamed";
    var file = try tmp_dir1.dir.createFile(io, test_file_name, .{ .read = true });
    file.close(io);
    try Dir.rename(tmp_dir1.dir, test_file_name, tmp_dir2.dir, renamed_test_file_name, io);

    // ensure the file was renamed
    try expectError(error.FileNotFound, tmp_dir1.dir.openFile(io, test_file_name, .{}));
    file = try tmp_dir2.dir.openFile(io, renamed_test_file_name, .{});
    file.close(io);
}

test "renameAbsolute" {
    if (!isRealPathSupported()) return error.SkipZigTest;

    const io = testing.io;

    var tmp_dir = tmpDir(.{});
    defer tmp_dir.cleanup();

    // Get base abs path
    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const base_path = try tmp_dir.dir.realPathFileAlloc(io, ".", allocator);

    try expectError(error.FileNotFound, Dir.renameAbsolute(
        try Dir.path.join(allocator, &.{ base_path, "missing_file_name" }),
        try Dir.path.join(allocator, &.{ base_path, "something_else" }),
        io,
    ));

    // Renaming files
    const test_file_name = "test_file";
    const renamed_test_file_name = "test_file_renamed";
    var file = try tmp_dir.dir.createFile(io, test_file_name, .{ .read = true });
    file.close(io);
    try Dir.renameAbsolute(
        try Dir.path.join(allocator, &.{ base_path, test_file_name }),
        try Dir.path.join(allocator, &.{ base_path, renamed_test_file_name }),
        io,
    );

    // ensure the file was renamed
    try expectError(error.FileNotFound, tmp_dir.dir.openFile(io, test_file_name, .{}));
    file = try tmp_dir.dir.openFile(io, renamed_test_file_name, .{});
    const stat = try file.stat(io);
    try expectEqual(File.Kind.file, stat.kind);
    file.close(io);

    // Renaming directories
    const test_dir_name = "test_dir";
    const renamed_test_dir_name = "test_dir_renamed";
    try tmp_dir.dir.createDir(io, test_dir_name, .default_dir);
    try Dir.renameAbsolute(
        try Dir.path.join(allocator, &.{ base_path, test_dir_name }),
        try Dir.path.join(allocator, &.{ base_path, renamed_test_dir_name }),
        io,
    );

    // ensure the directory was renamed
    try expectError(error.FileNotFound, tmp_dir.dir.openDir(io, test_dir_name, .{}));
    var dir = try tmp_dir.dir.openDir(io, renamed_test_dir_name, .{});
    dir.close(io);
}

test "openExecutable" {
    if (native_os == .wasi) return error.SkipZigTest;
    if (native_os == .openbsd) return error.SkipZigTest;

    const io = testing.io;

    const self_exe_file = try std.process.openExecutable(io, .{});
    self_exe_file.close(io);
}

test "executablePath" {
    if (native_os == .wasi) return error.SkipZigTest;
    if (native_os == .openbsd) return error.SkipZigTest;

    const io = testing.io;
    var buf: [Dir.max_path_bytes]u8 = undefined;
    const len = try std.process.executablePath(io, &buf);
    const buf_self_exe_path = buf[0..len];
    const alloc_self_exe_path = try std.process.executablePathAlloc(io, testing.allocator);
    defer testing.allocator.free(alloc_self_exe_path);
    try expectEqualSlices(u8, buf_self_exe_path, alloc_self_exe_path);
}

test "deleteTree does not follow symlinks" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "b");
    {
        var a = try tmp.dir.createDirPathOpen(io, "a", .{});
        defer a.close(io);

        try setupSymlink(io, a, "../b", "b", .{ .is_directory = true });
    }

    try tmp.dir.deleteTree(io, "a");

    try expectError(error.FileNotFound, tmp.dir.access(io, "a", .{}));
    try tmp.dir.access(io, "b", .{});
}

test "deleteTree on a symlink" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    // Symlink to a file
    try tmp.dir.writeFile(io, .{ .sub_path = "file", .data = "" });
    try setupSymlink(io, tmp.dir, "file", "filelink", .{});

    try tmp.dir.deleteTree(io, "filelink");
    try expectError(error.FileNotFound, tmp.dir.access(io, "filelink", .{}));
    try tmp.dir.access(io, "file", .{});

    // Symlink to a directory
    try tmp.dir.createDirPath(io, "dir");
    try setupSymlink(io, tmp.dir, "dir", "dirlink", .{ .is_directory = true });

    try tmp.dir.deleteTree(io, "dirlink");
    try expectError(error.FileNotFound, tmp.dir.access(io, "dirlink", .{}));
    try tmp.dir.access(io, "dir", .{});
}

test "createDirPath, put some files in it, deleteTree" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const allocator = ctx.arena.allocator();
            const dir_path = try ctx.transformPath("os_test_tmp");

            try ctx.dir.createDirPath(io, try Dir.path.join(allocator, &.{ "os_test_tmp", "b", "c" }));
            try ctx.dir.writeFile(io, .{
                .sub_path = try Dir.path.join(allocator, &.{ "os_test_tmp", "b", "c", "file.txt" }),
                .data = "nonsense",
            });
            try ctx.dir.writeFile(io, .{
                .sub_path = try Dir.path.join(allocator, &.{ "os_test_tmp", "b", "file2.txt" }),
                .data = "blah",
            });

            try ctx.dir.deleteTree(io, dir_path);
            try expectError(error.FileNotFound, ctx.dir.openDir(io, dir_path, .{}));
        }
    }.impl);
}

test "createDirPath, put some files in it, deleteTreeMinStackSize" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const allocator = ctx.arena.allocator();
            const dir_path = try ctx.transformPath("os_test_tmp");

            try ctx.dir.createDirPath(io, try Dir.path.join(allocator, &.{ "os_test_tmp", "b", "c" }));
            try ctx.dir.writeFile(io, .{
                .sub_path = try Dir.path.join(allocator, &.{ "os_test_tmp", "b", "c", "file.txt" }),
                .data = "nonsense",
            });
            try ctx.dir.writeFile(io, .{
                .sub_path = try Dir.path.join(allocator, &.{ "os_test_tmp", "b", "file2.txt" }),
                .data = "blah",
            });

            try ctx.dir.deleteTreeMinStackSize(io, dir_path);
            try expectError(error.FileNotFound, ctx.dir.openDir(io, dir_path, .{}));
        }
    }.impl);
}

test "createDirPath in a directory that no longer exists" {
    if (native_os == .windows) return error.SkipZigTest; // Windows returns FileBusy if attempting to remove an open dir
    if (native_os == .dragonfly) return error.SkipZigTest; // DragonflyBSD does not produce error (hammer2 fs)

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();
    try tmp.parent_dir.deleteTree(io, &tmp.sub_path);

    try expectError(error.FileNotFound, tmp.dir.createDirPath(io, "sub-path"));
}

test "createDirPath but sub_path contains pre-existing file" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "foo", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "foo/bar", .data = "" });

    try expectError(error.NotDir, tmp.dir.createDirPath(io, "foo/bar/baz"));
}

fn expectDir(io: Io, dir: Dir, path: []const u8) !void {
    var d = try dir.openDir(io, path, .{});
    d.close(io);
}

test "makepath existing directories" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "A", .default_dir);
    var tmpA = try tmp.dir.openDir(io, "A", .{});
    defer tmpA.close(io);
    try tmpA.createDir(io, "B", .default_dir);

    const testPath = "A" ++ Dir.path.sep_str ++ "B" ++ Dir.path.sep_str ++ "C";
    try tmp.dir.createDirPath(io, testPath);

    try expectDir(io, tmp.dir, testPath);
}

test "makepath through existing valid symlink" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "realfolder", .default_dir);
    try setupSymlink(io, tmp.dir, "." ++ Dir.path.sep_str ++ "realfolder", "working-symlink", .{});

    try tmp.dir.createDirPath(io, "working-symlink" ++ Dir.path.sep_str ++ "in-realfolder");

    try expectDir(io, tmp.dir, "realfolder" ++ Dir.path.sep_str ++ "in-realfolder");
}

test "makepath relative walks" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const relPath = try Dir.path.join(testing.allocator, &.{
        "first", "..", "second", "..", "third", "..", "first", "A", "..", "B", "..", "C",
    });
    defer testing.allocator.free(relPath);

    try tmp.dir.createDirPath(io, relPath);

    // How .. is handled is different on Windows than non-Windows
    switch (native_os) {
        .windows => {
            // On Windows, .. is resolved before passing the path to NtCreateFile,
            // meaning everything except `first/C` drops out.
            try expectDir(io, tmp.dir, "first" ++ Dir.path.sep_str ++ "C");
            try expectError(error.FileNotFound, tmp.dir.access(io, "second", .{}));
            try expectError(error.FileNotFound, tmp.dir.access(io, "third", .{}));
        },
        else => {
            try expectDir(io, tmp.dir, "first" ++ Dir.path.sep_str ++ "A");
            try expectDir(io, tmp.dir, "first" ++ Dir.path.sep_str ++ "B");
            try expectDir(io, tmp.dir, "first" ++ Dir.path.sep_str ++ "C");
            try expectDir(io, tmp.dir, "second");
            try expectDir(io, tmp.dir, "third");
        },
    }
}

test "makepath ignores '.'" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    // Path to create, with "." elements:
    const dotPath = try Dir.path.join(testing.allocator, &.{
        "first", ".", "second", ".", "third",
    });
    defer testing.allocator.free(dotPath);

    // Path to expect to find:
    const expectedPath = try Dir.path.join(testing.allocator, &.{
        "first", "second", "third",
    });
    defer testing.allocator.free(expectedPath);

    try tmp.dir.createDirPath(io, dotPath);

    try expectDir(io, tmp.dir, expectedPath);
}

fn testFilenameLimits(io: Io, iterable_dir: Dir, maxed_filename: []const u8, maxed_dirname: []const u8) !void {
    // create a file, a dir, and a nested file all with maxed filenames
    {
        try iterable_dir.writeFile(io, .{ .sub_path = maxed_filename, .data = "" });

        var maxed_dir = try iterable_dir.createDirPathOpen(io, maxed_dirname, .{});
        defer maxed_dir.close(io);

        try maxed_dir.writeFile(io, .{ .sub_path = maxed_filename, .data = "" });
    }
    // Low level API with minimum buffer length
    {
        var reader_buf: [Dir.Reader.min_buffer_len]u8 align(@alignOf(usize)) = undefined;
        var reader: Dir.Reader = .init(iterable_dir, &reader_buf);

        var file_count: usize = 0;
        var dir_count: usize = 0;
        while (try reader.next(io)) |entry| {
            switch (entry.kind) {
                .file => {
                    try expectEqualStrings(maxed_filename, entry.name);
                    file_count += 1;
                },
                .directory => {
                    try expectEqualStrings(maxed_dirname, entry.name);
                    dir_count += 1;
                },
                else => return error.TestFailed,
            }
        }
        try expectEqual(@as(usize, 1), file_count);
        try expectEqual(@as(usize, 1), dir_count);
    }
    // High level walk API
    {
        var walker = try iterable_dir.walk(testing.allocator);
        defer walker.deinit();

        var file_count: usize = 0;
        var dir_count: usize = 0;
        while (try walker.next(io)) |entry| {
            switch (entry.kind) {
                .file => {
                    try expectEqualStrings(maxed_filename, entry.basename);
                    file_count += 1;
                },
                .directory => {
                    try expectEqualStrings(maxed_dirname, entry.basename);
                    dir_count += 1;
                },
                else => return error.TestFailed,
            }
        }
        try expectEqual(@as(usize, 2), file_count);
        try expectEqual(@as(usize, 1), dir_count);
    }

    // ensure that we can delete the tree
    try iterable_dir.deleteTree(io, maxed_filename);
}

test "max file name component lengths" {
    const io = testing.io;

    var tmp = tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    if (native_os == .windows) {
        // U+FFFF is the character with the largest code point that is encoded as a single
        // WTF-16 code unit, so Windows allows for NAME_MAX of them.
        const maxed_windows_filename1 = ("\u{FFFF}".*) ** windows.NAME_MAX;
        // This is also a code point that is encoded as one WTF-16 code unit, but
        // three WTF-8 bytes, so it exercises the limits of both WTF-16 and WTF-8 encodings.
        const maxed_windows_filename2 = ("€".*) ** windows.NAME_MAX;
        try testFilenameLimits(io, tmp.dir, &maxed_windows_filename1, &maxed_windows_filename2);
    } else if (native_os == .wasi) {
        // On WASI, the maxed filename depends on the host OS, so in order for this test to
        // work on any host, we need to use a length that will work for all platforms
        // (i.e. the minimum max_name_bytes of all supported platforms).
        const maxed_wasi_filename1: [255]u8 = @splat('1');
        const maxed_wasi_filename2: [255]u8 = @splat('2');
        try testFilenameLimits(io, tmp.dir, &maxed_wasi_filename1, &maxed_wasi_filename2);
    } else {
        const maxed_ascii_filename1: [Dir.max_name_bytes]u8 = @splat('1');
        const maxed_ascii_filename2: [Dir.max_name_bytes]u8 = @splat('2');
        try testFilenameLimits(io, tmp.dir, &maxed_ascii_filename1, &maxed_ascii_filename2);
    }
}

test "writev, readv" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const line1 = "line1\n";
    const line2 = "line2\n";

    var buf1: [line1.len]u8 = undefined;
    var buf2: [line2.len]u8 = undefined;
    var write_vecs: [2][]const u8 = .{ line1, line2 };
    var read_vecs: [2][]u8 = .{ &buf2, &buf1 };

    var src_file = try tmp.dir.createFile(io, "test.txt", .{ .read = true });
    defer src_file.close(io);

    var writer = src_file.writerStreaming(io, &.{});

    try writer.interface.writeVecAll(&write_vecs);
    try writer.interface.flush();
    try expectEqual(@as(u64, line1.len + line2.len), try src_file.length(io));

    var reader = writer.moveToReader();
    try reader.seekTo(0);
    try reader.interface.readVecAll(&read_vecs);
    try expectEqualStrings(&buf1, "line2\n");
    try expectEqualStrings(&buf2, "line1\n");
    try expectError(error.EndOfStream, reader.interface.readSliceAll(&buf1));
}

test "pwritev, preadv" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const line1 = "line1\n";
    const line2 = "line2\n";
    var lines: [2][]const u8 = .{ line1, line2 };
    var buf1: [line1.len]u8 = undefined;
    var buf2: [line2.len]u8 = undefined;
    var read_vecs: [2][]u8 = .{ &buf2, &buf1 };

    var src_file = try tmp.dir.createFile(io, "test.txt", .{ .read = true });
    defer src_file.close(io);

    var writer = src_file.writer(io, &.{});

    try writer.seekTo(16);
    try writer.interface.writeVecAll(&lines);
    try writer.interface.flush();
    try expectEqual(@as(u64, 16 + line1.len + line2.len), try src_file.length(io));

    var reader = writer.moveToReader();
    try reader.seekTo(16);
    try reader.interface.readVecAll(&read_vecs);
    try expectEqualStrings(&buf1, "line2\n");
    try expectEqualStrings(&buf2, "line1\n");
    try expectError(error.EndOfStream, reader.interface.readSliceAll(&buf1));
}

test "access file" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const dir_path = try ctx.transformPath("os_test_tmp");
            const file_path = try ctx.transformPath("os_test_tmp" ++ Dir.path.sep_str ++ "file.txt");

            try ctx.dir.createDirPath(io, dir_path);
            try expectError(error.FileNotFound, ctx.dir.access(io, file_path, .{}));

            try ctx.dir.writeFile(io, .{ .sub_path = file_path, .data = "" });
            try ctx.dir.access(io, file_path, .{});
            try ctx.dir.deleteTree(io, dir_path);
        }
    }.impl);
}

test "sendfile" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "os_test_tmp");

    var dir = try tmp.dir.openDir(io, "os_test_tmp", .{});
    defer dir.close(io);

    const line1 = "line1\n";
    const line2 = "second line\n";
    var vecs = [_][]const u8{ line1, line2 };

    var src_file = try dir.createFile(io, "sendfile1.txt", .{ .read = true });
    defer src_file.close(io);
    {
        var fw = src_file.writer(io, &.{});
        try fw.interface.writeVecAll(&vecs);
    }

    var dest_file = try dir.createFile(io, "sendfile2.txt", .{ .read = true });
    defer dest_file.close(io);

    const header1 = "header1\n";
    const header2 = "second header\n";
    const trailer1 = "trailer1\n";
    const trailer2 = "second trailer\n";
    var headers: [2][]const u8 = .{ header1, header2 };
    var trailers: [2][]const u8 = .{ trailer1, trailer2 };

    var written_buf: [100]u8 = undefined;
    var file_reader = src_file.reader(io, &.{});
    var fallback_buffer: [50]u8 = undefined;
    var file_writer = dest_file.writer(io, &fallback_buffer);
    try file_writer.interface.writeVecAll(&headers);
    try file_reader.seekTo(1);
    try expectEqual(10, try file_writer.interface.sendFileAll(&file_reader, .limited(10)));
    try file_writer.interface.writeVecAll(&trailers);
    try file_writer.interface.flush();
    var fr = file_writer.moveToReader();
    try fr.seekTo(0);
    const amt = try fr.interface.readSliceShort(&written_buf);
    try expectEqualStrings("header1\nsecond header\nine1\nsecontrailer1\nsecond trailer\n", written_buf[0..amt]);
}

test "sendfile with buffered data" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "os_test_tmp");

    var dir = try tmp.dir.openDir(io, "os_test_tmp", .{});
    defer dir.close(io);

    var src_file = try dir.createFile(io, "sendfile1.txt", .{ .read = true });
    defer src_file.close(io);

    try src_file.writeStreamingAll(io, "AAAABBBB");

    var dest_file = try dir.createFile(io, "sendfile2.txt", .{ .read = true });
    defer dest_file.close(io);

    var src_buffer: [32]u8 = undefined;
    var file_reader = src_file.reader(io, &src_buffer);

    try file_reader.seekTo(0);
    try file_reader.interface.fill(8);

    var fallback_buffer: [32]u8 = undefined;
    var file_writer = dest_file.writer(io, &fallback_buffer);

    try expectEqual(4, try file_writer.interface.sendFileAll(&file_reader, .limited(4)));

    var written_buf: [8]u8 = undefined;
    var fr = file_writer.moveToReader();
    try fr.seekTo(0);
    const amt = try fr.interface.readSliceShort(&written_buf);

    try expectEqual(4, amt);
    try expectEqualSlices(u8, "AAAA", written_buf[0..amt]);
}

test "copyFile" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const data = "u6wj+JmdF3qHsFPE BUlH2g4gJCmEz0PP";
            const src_file = try ctx.transformPath("tmp_test_copy_file.txt");
            const dest_file = try ctx.transformPath("tmp_test_copy_file2.txt");
            const dest_file2 = try ctx.transformPath("tmp_test_copy_file3.txt");

            try ctx.dir.writeFile(io, .{ .sub_path = src_file, .data = data });
            defer ctx.dir.deleteFile(io, src_file) catch {};

            try ctx.dir.copyFile(src_file, ctx.dir, dest_file, io, .{});
            defer ctx.dir.deleteFile(io, dest_file) catch {};

            try ctx.dir.copyFile(src_file, ctx.dir, dest_file2, io, .{});
            defer ctx.dir.deleteFile(io, dest_file2) catch {};

            try expectFileContents(io, ctx.dir, dest_file, data);
            try expectFileContents(io, ctx.dir, dest_file2, data);
        }
    }.impl);
}

fn expectFileContents(io: Io, dir: Dir, file_path: []const u8, data: []const u8) !void {
    const contents = try dir.readFileAlloc(io, file_path, testing.allocator, .limited(1000));
    defer testing.allocator.free(contents);

    try expectEqualSlices(u8, data, contents);
}

test "AtomicFile" {
    if (native_os == .windows) return error.SkipZigTest; // https://codeberg.org/ziglang/zig/issues/31389

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const allocator = ctx.arena.allocator();
            const test_out_file = try ctx.transformPath("tmp_atomic_file_test_dest.txt");
            const test_content =
                \\ hello!
                \\ this is a test file
            ;

            // link() succeeds with no file already present
            {
                var af = try ctx.dir.createFileAtomic(io, test_out_file, .{ .replace = false });
                defer af.deinit(io);
                try af.file.writeStreamingAll(io, test_content);
                try af.link(io);
            }
            // link() returns error.PathAlreadyExists if file already present
            {
                var af = try ctx.dir.createFileAtomic(io, test_out_file, .{ .replace = false });
                defer af.deinit(io);
                try af.file.writeStreamingAll(io, test_content);
                try expectError(error.PathAlreadyExists, af.link(io));
            }
            // replace() succeeds if file already present
            {
                var af = try ctx.dir.createFileAtomic(io, test_out_file, .{ .replace = true });
                defer af.deinit(io);
                try af.file.writeStreamingAll(io, test_content);
                try af.replace(io);
            }
            const content = try ctx.dir.readFileAlloc(io, test_out_file, allocator, .limited(9999));
            try expectEqualStrings(test_content, content);

            try ctx.dir.deleteFile(io, test_out_file);
        }
    }.impl);
}

test "open file with exclusive nonblocking lock twice" {
    if (native_os == .wasi) return error.SkipZigTest;

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const filename = try ctx.transformPath("file_nonblocking_lock_test.txt");

            const file1 = try ctx.dir.createFile(io, filename, .{ .lock = .exclusive, .lock_nonblocking = true });
            defer file1.close(io);

            const file2 = ctx.dir.createFile(io, filename, .{ .lock = .exclusive, .lock_nonblocking = true });
            try expectError(error.WouldBlock, file2);
        }
    }.impl);
}

test "open file with shared and exclusive nonblocking lock" {
    if (native_os == .wasi) return error.SkipZigTest;

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const filename = try ctx.transformPath("file_nonblocking_lock_test.txt");

            const file1 = try ctx.dir.createFile(io, filename, .{ .lock = .shared, .lock_nonblocking = true });
            defer file1.close(io);

            const file2 = ctx.dir.createFile(io, filename, .{ .lock = .exclusive, .lock_nonblocking = true });
            try expectError(error.WouldBlock, file2);
        }
    }.impl);
}

test "open file with exclusive and shared nonblocking lock" {
    if (native_os == .wasi) return error.SkipZigTest;

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const filename = try ctx.transformPath("file_nonblocking_lock_test.txt");

            const file1 = try ctx.dir.createFile(io, filename, .{ .lock = .exclusive, .lock_nonblocking = true });
            defer file1.close(io);

            const file2 = ctx.dir.createFile(io, filename, .{ .lock = .shared, .lock_nonblocking = true });
            try expectError(error.WouldBlock, file2);
        }
    }.impl);
}

test "open file with exclusive lock twice, make sure second lock waits" {
    testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const filename = try ctx.transformPath("file_lock_test.txt");

            const file = try ctx.dir.createFile(io, filename, .{ .lock = .exclusive });
            errdefer file.close(io);

            const S = struct {
                fn checkFn(inner_ctx: *TestContext, path: []const u8, started: *Io.Event, locked: *Io.Event) !void {
                    started.set(inner_ctx.io);
                    const file1 = try inner_ctx.dir.createFile(inner_ctx.io, path, .{ .lock = .exclusive });

                    locked.set(inner_ctx.io);
                    file1.close(inner_ctx.io);
                }
            };

            var started: Io.Event = .unset;
            var locked: Io.Event = .unset;

            var t = try io.concurrent(S.checkFn, .{ ctx, filename, &started, &locked });
            defer t.cancel(io) catch {};

            // Wait for the spawned thread to start trying to acquire the exclusive file lock.
            // Then wait a bit to make sure that can't acquire it since we currently hold the file lock.
            try started.wait(io);
            try expectError(error.Timeout, locked.waitTimeout(io, .{ .duration = .{
                .raw = .fromMilliseconds(10),
                .clock = .awake,
            } }));

            // Release the file lock which should unlock the thread to lock it and set the locked event.
            file.close(io);
            try locked.wait(io);
            try t.await(io);
        }
    }.impl) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
        else => |e| return e,
    };
}

test "open file with exclusive nonblocking lock twice (absolute paths)" {
    if (native_os == .wasi) return error.SkipZigTest;

    const io = testing.io;

    var random_bytes: [12]u8 = undefined;
    io.random(&random_bytes);

    var random_b64: [std.base64.url_safe.Encoder.calcSize(random_bytes.len)]u8 = undefined;
    _ = std.base64.url_safe.Encoder.encode(&random_b64, &random_bytes);

    const sub_path = random_b64 ++ "-zig-test-absolute-paths.txt";

    const gpa = testing.allocator;

    const cwd = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(cwd);

    const filename = try Dir.path.resolve(gpa, &.{ cwd, sub_path });
    defer gpa.free(filename);

    defer Dir.deleteFileAbsolute(io, filename) catch {}; // createFileAbsolute can leave files on failures
    const file1 = try Dir.createFileAbsolute(io, filename, .{
        .lock = .exclusive,
        .lock_nonblocking = true,
    });

    const file2 = Dir.createFileAbsolute(io, filename, .{
        .lock = .exclusive,
        .lock_nonblocking = true,
    });
    file1.close(io);
    try expectError(error.WouldBlock, file2);
}

test "read from locked file" {
    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const filename = try ctx.transformPath("read_lock_file_test.txt");

            {
                const f = try ctx.dir.createFile(io, filename, .{ .read = true });
                defer f.close(io);
                var buffer: [1]u8 = undefined;
                _ = try f.readPositional(io, &.{&buffer}, 0);
            }
            {
                const f = try ctx.dir.createFile(io, filename, .{
                    .read = true,
                    .lock = .exclusive,
                });
                defer f.close(io);
                const f2 = try ctx.dir.openFile(io, filename, .{});
                defer f2.close(io);
                // On POSIX locks may be ignored, however on Windows they cause
                // LockViolation.
                var buffer: [1]u8 = undefined;
                if (builtin.os.tag == .windows) {
                    try expectError(error.LockViolation, f2.readPositional(io, &.{&buffer}, 0));
                } else {
                    try expectEqual(0, f2.readPositional(io, &.{&buffer}, 0));
                }
            }
        }
    }.impl);
}

test "use Lock.none to unlock files" {
    if (native_os == .wasi) return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    // Create a locked file.
    const test_file = try tmp.dir.createFile(io, "test_file", .{ .lock = .exclusive, .lock_nonblocking = true });
    defer test_file.close(io);

    // Attempt to unlock the file via fs.lock with Lock.none.
    try test_file.lock(io, .none);

    // Attempt to open the file now that it should be unlocked.
    const test_file2 = try tmp.dir.openFile(io, "test_file", .{ .lock = .exclusive, .lock_nonblocking = true });
    defer test_file2.close(io);

    // Make sure Lock.none works with tryLock as well.
    try testing.expect(try test_file2.tryLock(io, .none));

    // Attempt to open the file since it should be unlocked again.
    const test_file3 = try tmp.dir.openFile(io, "test_file", .{ .lock = .exclusive, .lock_nonblocking = true });
    test_file3.close(io);
}

test "walker" {
    const io = testing.io;

    var tmp = tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    // iteration order of walker is undefined, so need lookup maps to check against

    const expected_paths = std.StaticStringMap(usize).initComptime(.{
        .{ "dir1", 1 },
        .{ "dir2", 1 },
        .{ "dir3", 1 },
        .{ "dir4", 1 },
        .{ "dir3" ++ Dir.path.sep_str ++ "sub1", 2 },
        .{ "dir3" ++ Dir.path.sep_str ++ "sub2", 2 },
        .{ "dir3" ++ Dir.path.sep_str ++ "sub2" ++ Dir.path.sep_str ++ "subsub1", 3 },
    });

    const expected_basenames = std.StaticStringMap(void).initComptime(.{
        .{"dir1"},
        .{"dir2"},
        .{"dir3"},
        .{"dir4"},
        .{"sub1"},
        .{"sub2"},
        .{"subsub1"},
    });

    for (expected_paths.keys()) |key| {
        try tmp.dir.createDirPath(io, key);
    }

    var walker = try tmp.dir.walk(testing.allocator);
    defer walker.deinit();

    var num_walked: usize = 0;
    while (try walker.next(io)) |entry| {
        expect(expected_basenames.has(entry.basename)) catch |err| {
            std.debug.print("found unexpected basename: {f}\n", .{std.ascii.hexEscape(entry.basename, .lower)});
            return err;
        };
        expect(expected_paths.has(entry.path)) catch |err| {
            std.debug.print("found unexpected path: {f}\n", .{std.ascii.hexEscape(entry.path, .lower)});
            return err;
        };
        expectEqual(expected_paths.get(entry.path).?, entry.depth()) catch |err| {
            std.debug.print("path reported unexpected depth: {f}\n", .{std.ascii.hexEscape(entry.path, .lower)});
            return err;
        };
        // make sure that the entry.dir is the containing dir
        var entry_dir = try entry.dir.openDir(io, entry.basename, .{});
        defer entry_dir.close(io);
        num_walked += 1;
    }
    try expectEqual(expected_paths.kvs.len, num_walked);
}

test "selective walker, skip entries that start with ." {
    const io = testing.io;

    var tmp = tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const paths_to_create: []const []const u8 = &.{
        "dir1/foo/.git/ignored",
        ".hidden/bar",
        "a/b/c",
        "a/baz",
    };

    // iteration order of walker is undefined, so need lookup maps to check against

    const expected_paths = std.StaticStringMap(usize).initComptime(.{
        .{ "dir1", 1 },
        .{ "dir1" ++ Dir.path.sep_str ++ "foo", 2 },
        .{ "a", 1 },
        .{ "a" ++ Dir.path.sep_str ++ "b", 2 },
        .{ "a" ++ Dir.path.sep_str ++ "b" ++ Dir.path.sep_str ++ "c", 3 },
        .{ "a" ++ Dir.path.sep_str ++ "baz", 2 },
    });

    const expected_basenames = std.StaticStringMap(void).initComptime(.{
        .{"dir1"},
        .{"foo"},
        .{"a"},
        .{"b"},
        .{"c"},
        .{"baz"},
    });

    for (paths_to_create) |path| {
        try tmp.dir.createDirPath(io, path);
    }

    var walker = try tmp.dir.walkSelectively(testing.allocator);
    defer walker.deinit();

    var num_walked: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.basename[0] == '.') continue;
        if (entry.kind == .directory) {
            try walker.enter(io, entry);
        }

        expect(expected_basenames.has(entry.basename)) catch |err| {
            std.debug.print("found unexpected basename: {f}\n", .{std.ascii.hexEscape(entry.basename, .lower)});
            return err;
        };
        expect(expected_paths.has(entry.path)) catch |err| {
            std.debug.print("found unexpected path: {f}\n", .{std.ascii.hexEscape(entry.path, .lower)});
            return err;
        };
        expectEqual(expected_paths.get(entry.path).?, entry.depth()) catch |err| {
            std.debug.print("path reported unexpected depth: {f}\n", .{std.ascii.hexEscape(entry.path, .lower)});
            return err;
        };

        // make sure that the entry.dir is the containing dir
        var entry_dir = try entry.dir.openDir(io, entry.basename, .{});
        defer entry_dir.close(io);
        num_walked += 1;
    }
    try expectEqual(expected_paths.kvs.len, num_walked);
}

test "walker without fully iterating" {
    const io = testing.io;

    var tmp = tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    var walker = try tmp.dir.walk(testing.allocator);
    defer walker.deinit();

    // Create 2 directories inside the tmp directory, but then only iterate once before breaking.
    // This ensures that walker doesn't try to close the initial directory when not fully iterating.

    try tmp.dir.createDirPath(io, "a");
    try tmp.dir.createDirPath(io, "b");

    var num_walked: usize = 0;
    while (try walker.next(io)) |_| {
        num_walked += 1;
        break;
    }
    try expectEqual(@as(usize, 1), num_walked);
}

test "'.' and '..' in Dir functions" {
    if (native_os == .windows) {
        // https://codeberg.org/ziglang/zig/issues/31561
        return error.SkipZigTest;
    }

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            const subdir_path = try ctx.transformPath("./subdir");
            const file_path = try ctx.transformPath("./subdir/../file");
            const copy_path = try ctx.transformPath("./subdir/../copy");
            const rename_path = try ctx.transformPath("./subdir/../rename");
            const update_path = try ctx.transformPath("./subdir/../update");

            try ctx.dir.createDir(io, subdir_path, .default_dir);
            try ctx.dir.access(io, subdir_path, .{});
            var created_subdir = try ctx.dir.openDir(io, subdir_path, .{});
            created_subdir.close(io);

            const created_file = try ctx.dir.createFile(io, file_path, .{});
            created_file.close(io);
            try ctx.dir.access(io, file_path, .{});

            try ctx.dir.copyFile(file_path, ctx.dir, copy_path, io, .{});
            try ctx.dir.rename(copy_path, ctx.dir, rename_path, io);
            const renamed_file = try ctx.dir.openFile(io, rename_path, .{});
            renamed_file.close(io);
            try ctx.dir.deleteFile(io, rename_path);

            try ctx.dir.writeFile(io, .{ .sub_path = update_path, .data = "something" });
            var dir = ctx.dir;
            const prev_status = try dir.updateFile(io, file_path, dir, update_path, .{});
            try expectEqual(Dir.PrevStatus.stale, prev_status);

            try ctx.dir.deleteDir(io, subdir_path);
        }
    }.impl);
}

test "'.' and '..' in absolute functions" {
    if (!isRealPathSupported()) return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const base_path = try tmp.dir.realPathFileAlloc(io, ".", allocator);

    const subdir_path = try Dir.path.join(allocator, &.{ base_path, "./subdir" });
    try Dir.createDirAbsolute(io, subdir_path, .default_dir);
    try Dir.accessAbsolute(io, subdir_path, .{});
    var created_subdir = try Dir.openDirAbsolute(io, subdir_path, .{});
    created_subdir.close(io);

    const created_file_path = try Dir.path.join(allocator, &.{ subdir_path, "../file" });
    const created_file = try Dir.createFileAbsolute(io, created_file_path, .{});
    created_file.close(io);
    try Dir.accessAbsolute(io, created_file_path, .{});

    const copied_file_path = try Dir.path.join(allocator, &.{ subdir_path, "../copy" });
    try Dir.copyFileAbsolute(created_file_path, copied_file_path, io, .{});
    const renamed_file_path = try Dir.path.join(allocator, &.{ subdir_path, "../rename" });
    try Dir.renameAbsolute(copied_file_path, renamed_file_path, io);
    const renamed_file = try Dir.openFileAbsolute(io, renamed_file_path, .{});
    renamed_file.close(io);
    try Dir.deleteFileAbsolute(io, renamed_file_path);

    try Dir.deleteDirAbsolute(io, subdir_path);
}

test "chmod" {
    if (native_os == .windows or native_os == .wasi) return;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile(io, "test_file", .{ .permissions = .fromMode(0o600) });
    defer file.close(io);
    try expectEqual(0o600, (try file.stat(io)).permissions.toMode() & 0o7777);

    try file.setPermissions(io, .fromMode(0o644));
    try expectEqual(0o644, (try file.stat(io)).permissions.toMode() & 0o7777);

    try tmp.dir.createDir(io, "test_dir", .default_dir);
    var dir = try tmp.dir.openDir(io, "test_dir", .{ .iterate = true });
    defer dir.close(io);

    try dir.setPermissions(io, .fromMode(0o700));
    try expectEqual(0o700, (try dir.stat(io)).permissions.toMode() & 0o7777);
}

test "change ownership" {
    if (native_os == .windows or native_os == .wasi)
        return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile(io, "test_file", .{});
    defer file.close(io);
    try file.setOwner(io, null, null);

    try tmp.dir.createDir(io, "test_dir", .default_dir);

    var dir = try tmp.dir.openDir(io, "test_dir", .{ .iterate = true });
    defer dir.close(io);
    try dir.setOwner(io, null, null);
}

test "invalid UTF-8/WTF-8 paths" {
    const expected_err = switch (native_os) {
        .wasi => error.BadPathName,
        .windows => error.BadPathName,
        else => return error.SkipZigTest,
    };

    try testWithAllSupportedPathTypes(struct {
        fn impl(ctx: *TestContext) !void {
            const io = ctx.io;
            // This is both invalid UTF-8 and WTF-8, since \xFF is an invalid start byte
            const invalid_path = try ctx.transformPath("\xFF");

            try expectError(expected_err, ctx.dir.openFile(io, invalid_path, .{}));

            try expectError(expected_err, ctx.dir.createFile(io, invalid_path, .{}));

            try expectError(expected_err, ctx.dir.createDir(io, invalid_path, .default_dir));

            try expectError(expected_err, ctx.dir.createDirPath(io, invalid_path));
            try expectError(expected_err, ctx.dir.createDirPathOpen(io, invalid_path, .{}));

            try expectError(expected_err, ctx.dir.openDir(io, invalid_path, .{}));

            try expectError(expected_err, ctx.dir.deleteFile(io, invalid_path));

            try expectError(expected_err, ctx.dir.deleteDir(io, invalid_path));

            try expectError(expected_err, ctx.dir.rename(invalid_path, ctx.dir, invalid_path, io));

            try expectError(expected_err, ctx.dir.symLink(io, invalid_path, invalid_path, .{}));

            try expectError(expected_err, ctx.dir.readLink(io, invalid_path, &[_]u8{}));

            try expectError(expected_err, ctx.dir.readFile(io, invalid_path, &[_]u8{}));
            try expectError(expected_err, ctx.dir.readFileAlloc(io, invalid_path, testing.allocator, .limited(0)));

            try expectError(expected_err, ctx.dir.deleteTree(io, invalid_path));
            try expectError(expected_err, ctx.dir.deleteTreeMinStackSize(io, invalid_path));

            try expectError(expected_err, ctx.dir.writeFile(io, .{ .sub_path = invalid_path, .data = "" }));

            try expectError(expected_err, ctx.dir.access(io, invalid_path, .{}));

            var dir = ctx.dir;
            try expectError(expected_err, dir.updateFile(io, invalid_path, dir, invalid_path, .{}));
            try expectError(expected_err, ctx.dir.copyFile(invalid_path, ctx.dir, invalid_path, io, .{}));

            try expectError(expected_err, ctx.dir.statFile(io, invalid_path, .{}));

            if (native_os != .wasi) {
                try expectError(expected_err, ctx.dir.realPathFile(io, invalid_path, &[_]u8{}));
                try expectError(expected_err, ctx.dir.realPathFileAlloc(io, invalid_path, testing.allocator));
            }

            try expectError(expected_err, Dir.rename(ctx.dir, invalid_path, ctx.dir, invalid_path, io));

            if (native_os != .wasi and ctx.path_type != .relative) {
                var buf: [Dir.max_path_bytes]u8 = undefined;
                try expectError(expected_err, Dir.copyFileAbsolute(invalid_path, invalid_path, io, .{}));
                try expectError(expected_err, Dir.createDirAbsolute(io, invalid_path, .default_dir));
                try expectError(expected_err, Dir.deleteDirAbsolute(io, invalid_path));
                try expectError(expected_err, Dir.renameAbsolute(invalid_path, invalid_path, io));
                try expectError(expected_err, Dir.openDirAbsolute(io, invalid_path, .{}));
                try expectError(expected_err, Dir.openFileAbsolute(io, invalid_path, .{}));
                try expectError(expected_err, Dir.accessAbsolute(io, invalid_path, .{}));
                try expectError(expected_err, Dir.createFileAbsolute(io, invalid_path, .{}));
                try expectError(expected_err, Dir.deleteFileAbsolute(io, invalid_path));
                try expectError(expected_err, Dir.readLinkAbsolute(io, invalid_path, &buf));
                try expectError(expected_err, Dir.symLinkAbsolute(io, invalid_path, invalid_path, .{}));
                try expectError(expected_err, Dir.realPathFileAbsolute(io, invalid_path, &buf));
                try expectError(expected_err, Dir.realPathFileAbsoluteAlloc(io, invalid_path, testing.allocator));
            }
        }
    }.impl);
}

test "read file non vectored" {
    const io = std.testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const contents = "hello, world!\n";

    const file = try tmp_dir.dir.createFile(io, "input.txt", .{ .read = true });
    defer file.close(io);
    {
        var file_writer: File.Writer = .init(file, io, &.{});
        try file_writer.interface.writeAll(contents);
        try file_writer.interface.flush();
    }

    var file_reader: std.Io.File.Reader = .init(file, io, &.{});

    var write_buffer: [100]u8 = undefined;
    var w: std.Io.Writer = .fixed(&write_buffer);

    var i: usize = 0;
    while (true) {
        i += file_reader.interface.stream(&w, .limited(3)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
    }
    try expectEqualStrings(contents, w.buffered());
    try expectEqual(contents.len, i);
}

test "seek keeping partial buffer" {
    const io = std.testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const contents = "0123456789";

    const file = try tmp_dir.dir.createFile(io, "input.txt", .{ .read = true });
    defer file.close(io);
    {
        var file_writer: File.Writer = .init(file, io, &.{});
        try file_writer.interface.writeAll(contents);
        try file_writer.interface.flush();
    }

    var read_buffer: [3]u8 = undefined;
    var file_reader: Io.File.Reader = .init(file, io, &read_buffer);

    try expectEqual(0, file_reader.logicalPos());

    var buf: [4]u8 = undefined;
    try file_reader.interface.readSliceAll(&buf);

    if (file_reader.interface.bufferedLen() != 3) {
        // Pass the test if the OS doesn't give us vectored reads.
        return;
    }

    try expectEqual(4, file_reader.logicalPos());
    try expectEqual(7, file_reader.pos);
    try file_reader.seekTo(6);
    try expectEqual(6, file_reader.logicalPos());
    try expectEqual(7, file_reader.pos);

    try expectEqualStrings("0123", &buf);

    const n = try file_reader.interface.readSliceShort(&buf);
    try expectEqual(4, n);

    try expectEqualStrings("6789", &buf);
}

test "seekBy" {
    const io = testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(io, .{ .sub_path = "blah.txt", .data = "let's test seekBy" });
    const f = try tmp_dir.dir.openFile(io, "blah.txt", .{ .mode = .read_only });
    defer f.close(io);
    var reader = f.readerStreaming(io, &.{});
    try reader.seekBy(2);

    var buffer: [20]u8 = undefined;
    const n = try reader.interface.readSliceShort(&buffer);
    try expectEqual(15, n);
    try expectEqualStrings("t's test seekBy", buffer[0..15]);
}

test "seekTo flushes buffered data" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = std.testing.io;

    const contents = "data";

    const file = try tmp.dir.createFile(io, "seek.bin", .{ .read = true });
    defer file.close(io);
    {
        var buf: [16]u8 = undefined;
        var file_writer = file.writer(io, &buf);

        try file_writer.interface.writeAll(contents);
        try file_writer.seekTo(8);
        try file_writer.interface.flush();
    }

    var read_buffer: [16]u8 = undefined;
    var file_reader: std.Io.File.Reader = .init(file, io, &read_buffer);

    var buf: [4]u8 = undefined;
    try file_reader.interface.readSliceAll(&buf);
    try expectEqualStrings(contents, &buf);
}

test "File.Writer sendfile with buffered contents" {
    const io = testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    {
        try tmp_dir.dir.writeFile(io, .{ .sub_path = "a", .data = "bcd" });
        const in = try tmp_dir.dir.openFile(io, "a", .{});
        defer in.close(io);
        const out = try tmp_dir.dir.createFile(io, "b", .{});
        defer out.close(io);

        var in_buf: [2]u8 = undefined;
        var in_r = in.reader(io, &in_buf);
        _ = try in_r.getSize(); // Catch seeks past end by populating size
        try in_r.interface.fill(2);

        var out_buf: [1]u8 = undefined;
        var out_w = out.writerStreaming(io, &out_buf);
        try out_w.interface.writeByte('a');
        try expectEqual(3, try out_w.interface.sendFileAll(&in_r, .unlimited));
        try out_w.interface.flush();
    }

    var check = try tmp_dir.dir.openFile(io, "b", .{});
    defer check.close(io);
    var check_buf: [4]u8 = undefined;
    var check_r = check.reader(io, &check_buf);
    try expectEqualStrings("abcd", try check_r.interface.take(4));
    try expectError(error.EndOfStream, check_r.interface.takeByte());
}

test "readlink on Windows" {
    if (native_os != .windows) return error.SkipZigTest;

    const io = testing.io;

    try testReadLinkWindows(io, "C:\\ProgramData", "C:\\Users\\All Users");
    try testReadLinkWindows(io, "C:\\Users\\Default", "C:\\Users\\Default User");
    try testReadLinkWindows(io, "C:\\Users", "C:\\Documents and Settings");
}

fn testReadLinkWindows(io: Io, target_path: []const u8, symlink_path: []const u8) !void {
    var buffer: [Dir.max_path_bytes]u8 = undefined;
    const len = try Dir.readLinkAbsolute(io, symlink_path, &buffer);
    const given = buffer[0..len];
    try expect(mem.eql(u8, target_path, given));
}

test "readlinkat" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    // create file
    try tmp.dir.writeFile(io, .{ .sub_path = "file.txt", .data = "nonsense" });

    // create a symbolic link
    try setupSymlink(io, tmp.dir, "file.txt", "link", .{});

    // read the link
    var buffer: [Dir.max_path_bytes]u8 = undefined;
    const read_link = buffer[0..try tmp.dir.readLink(io, "link", &buffer)];
    try expectEqualStrings("file.txt", read_link);
}

test "fchmodat smoke test" {
    if (!Io.File.Permissions.has_executable_bit) return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    try expectError(error.FileNotFound, tmp.dir.setFilePermissions(io, "regfile", .fromMode(0o666), .{}));
    const file = try tmp.dir.createFile(io, "regfile", .{
        .exclusive = true,
        .permissions = .fromMode(0o644),
    });
    file.close(io);

    if ((builtin.cpu.arch == .riscv32 or builtin.cpu.arch.isLoongArch()) and
        builtin.os.tag == .linux and !builtin.link_libc)
    {
        return error.SkipZigTest; // No `fstatat()`.
    }

    try tmp.dir.symLink(io, "regfile", "symlink", .{});
    const sym_mode = blk: {
        const st = try tmp.dir.statFile(io, "symlink", .{ .follow_symlinks = false });
        break :blk st.permissions.toMode() & 0b111_111_111;
    };

    try tmp.dir.setFilePermissions(io, "regfile", .fromMode(0o640), .{});
    try expectMode(io, tmp.dir, "regfile", .fromMode(0o640));
    try tmp.dir.setFilePermissions(io, "regfile", .fromMode(0o600), .{ .follow_symlinks = false });
    try expectMode(io, tmp.dir, "regfile", .fromMode(0o600));

    try tmp.dir.setFilePermissions(io, "symlink", .fromMode(0o640), .{});
    try expectMode(io, tmp.dir, "regfile", .fromMode(0o640));
    try expectMode(io, tmp.dir, "symlink", .fromMode(sym_mode));

    var test_link = true;
    tmp.dir.setFilePermissions(io, "symlink", .fromMode(0o600), .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.OperationUnsupported => test_link = false,
        else => |e| return e,
    };
    if (test_link) try expectMode(io, tmp.dir, "symlink", .fromMode(0o600));
    try expectMode(io, tmp.dir, "regfile", .fromMode(0o640));
}

fn expectMode(io: Io, dir: Dir, file: []const u8, permissions: File.Permissions) !void {
    const mode = permissions.toMode();
    const st = try dir.statFile(io, file, .{ .follow_symlinks = false });
    const found_mode = st.permissions.toMode();
    try expectEqual(mode, found_mode & 0b111_111_111);
}

test "isatty" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(io, "foo", .{});
    defer file.close(io);

    try expectEqual(false, try file.isTty(io));
}

test "read positional empty buffer" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(io, "pread_empty", .{ .read = true });
    defer file.close(io);

    var buffer: [0]u8 = undefined;
    try expectEqual(0, try file.readPositional(io, &.{&buffer}, 0));
}

test "write streaming empty buffer" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(io, "write_empty", .{});
    defer file.close(io);

    const buffer: [0]u8 = .{};
    try file.writeStreamingAll(io, &buffer);
}

test "write positional empty buffer" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(io, "pwrite_empty", .{});
    defer file.close(io);

    const buffer: [0]u8 = .{};
    try expectEqual(0, try file.writePositional(io, &.{&buffer}, 0));
}

test "access smoke test" {
    if (native_os == .wasi) return error.SkipZigTest;
    if (native_os == .windows) return error.SkipZigTest;
    if (native_os == .openbsd) return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    {
        // Create some file using `open`.
        const file = try tmp.dir.createFile(io, "some_file", .{ .read = true, .exclusive = true });
        file.close(io);
    }

    {
        // Try to access() the file
        if (native_os == .windows) {
            try tmp.dir.access(io, "some_file", .{});
        } else {
            try tmp.dir.access(io, "some_file", .{ .read = true, .write = true });
        }
    }

    {
        // Try to access() a non-existent file - should fail with error.FileNotFound
        try expectError(error.FileNotFound, tmp.dir.access(io, "some_other_file", .{}));
    }

    {
        // Create some directory
        try tmp.dir.createDir(io, "some_dir", .default_dir);
    }

    {
        // Try to access() the directory
        try tmp.dir.access(io, "some_dir", .{});
    }
}

test "write streaming a long vector" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(io, "pwritev", .{});
    defer file.close(io);

    var vecs: [2000][]const u8 = undefined;
    for (&vecs) |*v| v.* = "a";

    const n = try file.writePositional(io, &vecs, 0);
    try expect(n <= vecs.len);
}

test "open smoke test" {
    if (native_os == .wasi) return error.SkipZigTest;
    if (native_os == .windows) return error.SkipZigTest;
    if (native_os == .openbsd) return error.SkipZigTest;

    // TODO verify file attributes using `fstat`

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const io = testing.io;

    {
        // Create some file using `open`.
        const file = try tmp.dir.createFile(io, "some_file", .{ .exclusive = true });
        file.close(io);
    }

    // Try this again with the same flags. This op should fail with error.PathAlreadyExists.
    try expectError(
        error.PathAlreadyExists,
        tmp.dir.createFile(io, "some_file", .{ .exclusive = true }),
    );

    {
        // Try opening without exclusive flag.
        const file = try tmp.dir.createFile(io, "some_file", .{});
        file.close(io);
    }

    try expectError(error.NotDir, tmp.dir.openDir(io, "some_file", .{}));
    try tmp.dir.createDir(io, "some_dir", .default_dir);

    {
        const dir = try tmp.dir.openDir(io, "some_dir", .{});
        dir.close(io);
    }

    // Try opening as file which should fail.
    try expectError(error.IsDir, tmp.dir.openFile(io, "some_dir", .{ .allow_directory = false }));
}

test "hard link with different directories" {
    if (native_os == .wasi or native_os == .windows) return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const target_name = "link-target";
    const link_name = "newlink";

    const subdir = try tmp.dir.createDirPathOpen(io, "subdir", .{});

    defer tmp.dir.deleteFile(io, target_name) catch {};
    try tmp.dir.writeFile(io, .{ .sub_path = target_name, .data = "example" });

    // Test 1: link from file in subdir back up to target in parent directory
    tmp.dir.hardLink(target_name, subdir, link_name, io, .{}) catch |err| switch (err) {
        error.OperationUnsupported => return error.SkipZigTest,
        else => |e| return e,
    };

    const efd = try tmp.dir.openFile(io, target_name, .{});
    defer efd.close(io);

    const nfd = try subdir.openFile(io, link_name, .{});
    defer nfd.close(io);

    {
        const e_stat = try efd.stat(io);
        const n_stat = try nfd.stat(io);

        try expectEqual(e_stat.inode, n_stat.inode);
        try expectEqual(2, e_stat.nlink);
        try expectEqual(2, n_stat.nlink);
    }

    // Test 2: remove link
    try subdir.deleteFile(io, link_name);
    const e_stat = try efd.stat(io);
    try expectEqual(1, e_stat.nlink);
}

test "stat smoke test" {
    if (native_os == .wasi and !builtin.link_libc) return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    // create dummy file
    const contents = "nonsense";
    try tmp.dir.writeFile(io, .{ .sub_path = "file.txt", .data = contents });

    // fetch file's info on the opened fd directly
    const file = try tmp.dir.openFile(io, "file.txt", .{});
    const stat = try file.stat(io);
    defer file.close(io);

    // now repeat but using directory handle instead
    const statat = try tmp.dir.statFile(io, "file.txt", .{ .follow_symlinks = false });

    try expectEqual(stat.inode, statat.inode);
    try expectEqual(stat.nlink, statat.nlink);
    try expectEqual(stat.size, statat.size);
    try expectEqual(stat.permissions, statat.permissions);
    try expectEqual(stat.kind, statat.kind);
    try expectEqual(stat.atime, statat.atime);
    try expectEqual(stat.mtime, statat.mtime);
    try expectEqual(stat.ctime, statat.ctime);
}
