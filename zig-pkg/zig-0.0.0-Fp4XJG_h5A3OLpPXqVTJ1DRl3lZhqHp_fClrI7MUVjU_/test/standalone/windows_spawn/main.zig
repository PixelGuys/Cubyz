const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const windows = std.os.windows;
const utf16Literal = std.unicode.utf8ToUtf16LeStringLiteral;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const process_cwd_path = try std.process.currentPathAlloc(io, init.arena.allocator());

    var it = try init.minimal.args.iterateAllocator(gpa);
    defer it.deinit();
    _ = it.next() orelse unreachable; // skip binary name
    const hello_exe_cache_path = it.next() orelse unreachable;
    const tmp_dir_path = it.next() orelse unreachable;

    var tmp_dir = try Io.Dir.cwd().openDir(io, tmp_dir_path, .{});
    defer tmp_dir.close(io);

    const tmp_absolute_path = try tmp_dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(tmp_absolute_path);
    const tmp_absolute_path_w = try std.unicode.utf8ToUtf16LeAllocZ(gpa, tmp_absolute_path);
    defer gpa.free(tmp_absolute_path_w);
    const cwd_absolute_path = try Io.Dir.cwd().realPathFileAlloc(io, ".", gpa);
    defer gpa.free(cwd_absolute_path);
    const tmp_relative_path = try std.fs.path.relative(gpa, process_cwd_path, init.environ_map, cwd_absolute_path, tmp_absolute_path);
    defer gpa.free(tmp_relative_path);

    // Clear PATH
    std.debug.assert(SetEnvironmentVariableW(utf16Literal("PATH"), null).toBool());

    // Set PATHEXT to something predictable
    std.debug.assert(SetEnvironmentVariableW(utf16Literal("PATHEXT"), utf16Literal(".COM;.EXE;.BAT;.CMD;.JS")).toBool());

    // No PATH, so it should fail to find anything not in the cwd
    try testExecError(error.FileNotFound, gpa, io, "something_missing");

    // make sure we don't get error.BadPath traversing out of cwd with a relative path
    try testExecError(error.FileNotFound, gpa, io, "..\\.\\.\\.\\\\..\\more_missing");

    std.debug.assert(SetEnvironmentVariableW(utf16Literal("PATH"), tmp_absolute_path_w).toBool());

    // Move hello.exe into the tmp dir which is now added to the path
    try Io.Dir.cwd().copyFile(hello_exe_cache_path, tmp_dir, "hello.exe", io, .{});

    // with extension should find the .exe (case insensitive)
    try testExec(gpa, io, "HeLLo.exe", "hello from exe\n");
    // without extension should find the .exe (case insensitive)
    try testExec(gpa, io, "heLLo", "hello from exe\n");
    // with invalid cwd
    try std.testing.expectError(error.FileNotFound, testExecWithCwd(gpa, io, "hello.exe", "missing_dir", ""));

    // now add a .bat
    try tmp_dir.writeFile(io, .{ .sub_path = "hello.bat", .data = "@echo hello from bat" });
    // and a .cmd
    try tmp_dir.writeFile(io, .{ .sub_path = "hello.cmd", .data = "@echo hello from cmd" });

    // with extension should find the .bat (case insensitive)
    try testExec(gpa, io, "heLLo.bat", "hello from bat\r\n");
    // with extension should find the .cmd (case insensitive)
    try testExec(gpa, io, "heLLo.cmd", "hello from cmd\r\n");
    // without extension should find the .exe (since its first in PATHEXT)
    try testExec(gpa, io, "heLLo", "hello from exe\n");

    // now rename the exe to not have an extension
    try renameExe(tmp_dir, io, "hello.exe", "hello");

    // with extension should now fail
    try testExecError(error.FileNotFound, gpa, io, "hello.exe");
    // without extension should succeed (case insensitive)
    try testExec(gpa, io, "heLLo", "hello from exe\n");

    try tmp_dir.createDir(io, "something", .default_dir);
    try renameExe(tmp_dir, io, "hello", "something/hello.exe");

    const relative_path_no_ext = try std.fs.path.join(gpa, &.{ tmp_relative_path, "something/hello" });
    defer gpa.free(relative_path_no_ext);

    // Giving a full relative path to something/hello should work
    try testExec(gpa, io, relative_path_no_ext, "hello from exe\n");
    // But commands with path separators get excluded from PATH searching, so this will fail
    try testExecError(error.FileNotFound, gpa, io, "something/hello");

    // Now that .BAT is the first PATHEXT that should be found, this should succeed
    try testExec(gpa, io, "heLLo", "hello from bat\r\n");

    // Add a hello.exe that is not a valid executable
    try tmp_dir.writeFile(io, .{ .sub_path = "hello.exe", .data = "invalid" });

    // Trying to execute it with extension will give InvalidExe. This is a special
    // case for .EXE extensions, where if they ever try to get executed but they are
    // invalid, that gets treated as a fatal error wherever they are found and InvalidExe
    // is returned immediately.
    try testExecError(error.InvalidExe, gpa, io, "hello.exe");
    // Same thing applies to the command with no extension--even though there is a
    // hello.bat that could be executed, it should stop after it tries executing
    // hello.exe and getting InvalidExe.
    try testExecError(error.InvalidExe, gpa, io, "hello");

    // If we now rename hello.exe to have no extension, it will behave differently
    try renameExe(tmp_dir, io, "hello.exe", "hello");

    // Now, trying to execute it without an extension should treat InvalidExe as recoverable
    // and skip over it and find hello.bat and execute that
    try testExec(gpa, io, "hello", "hello from bat\r\n");

    // If we rename the invalid exe to something else
    try renameExe(tmp_dir, io, "hello", "goodbye");
    // Then we should now get FileNotFound when trying to execute 'goodbye',
    // since that is what the original error will be after searching for 'goodbye'
    // in the cwd. It will try to execute 'goodbye' from the PATH but the InvalidExe error
    // should be ignored in this case.
    try testExecError(error.FileNotFound, gpa, io, "goodbye");

    // Now let's set the tmp dir as the cwd and set the path only include the "something" sub dir
    try std.process.setCurrentDir(io, tmp_dir);
    defer std.process.setCurrentPath(io, process_cwd_path) catch {};
    const something_subdir_abs_path = try std.mem.concatWithSentinel(gpa, u16, &.{ tmp_absolute_path_w, utf16Literal("\\something") }, 0);
    defer gpa.free(something_subdir_abs_path);

    std.debug.assert(SetEnvironmentVariableW(utf16Literal("PATH"), something_subdir_abs_path).toBool());

    // Now trying to execute goodbye should give error.InvalidExe since it's the original
    // error that we got when trying within the cwd
    try testExecError(error.InvalidExe, gpa, io, "goodbye");

    // hello should still find the .bat
    try testExec(gpa, io, "hello", "hello from bat\r\n");

    // If we rename something/hello.exe to something/goodbye.exe
    try renameExe(tmp_dir, io, "something/hello.exe", "something/goodbye.exe");
    // And try to execute goodbye, then the one in something should be found
    // since the one in cwd is an invalid executable
    try testExec(gpa, io, "goodbye", "hello from exe\n");

    // If we use an absolute path to execute the invalid goodbye
    const goodbye_abs_path = try std.mem.join(gpa, "\\", &.{ tmp_absolute_path, "goodbye" });
    defer gpa.free(goodbye_abs_path);
    // then the PATH should not be searched and we should get InvalidExe
    try testExecError(error.InvalidExe, gpa, io, goodbye_abs_path);

    // If we try to exec but provide a cwd that is an absolute path, the PATH
    // should still be searched and the goodbye.exe in something should be found.
    try testExecWithCwd(gpa, io, "goodbye", tmp_absolute_path, "hello from exe\n");

    // introduce some extra path separators into the path which is dealt with inside the spawn call.
    const denormed_something_subdir_size = std.mem.replacementSize(u16, something_subdir_abs_path, utf16Literal("\\"), utf16Literal("\\\\\\\\"));

    const denormed_something_subdir_abs_path = try gpa.allocSentinel(u16, denormed_something_subdir_size, 0);
    defer gpa.free(denormed_something_subdir_abs_path);

    _ = std.mem.replace(u16, something_subdir_abs_path, utf16Literal("\\"), utf16Literal("\\\\\\\\"), denormed_something_subdir_abs_path);

    const denormed_something_subdir_wtf8 = try std.unicode.wtf16LeToWtf8Alloc(gpa, denormed_something_subdir_abs_path);
    defer gpa.free(denormed_something_subdir_wtf8);

    // clear the path to ensure that the match comes from the cwd
    std.debug.assert(SetEnvironmentVariableW(utf16Literal("PATH"), null).toBool());

    try testExecWithCwd(gpa, io, "goodbye", denormed_something_subdir_wtf8, "hello from exe\n");

    // normalization should also work if the non-normalized path is found in the PATH var.
    std.debug.assert(SetEnvironmentVariableW(utf16Literal("PATH"), denormed_something_subdir_abs_path).toBool());
    try testExec(gpa, io, "goodbye", "hello from exe\n");

    // now make sure we can launch executables "outside" of the cwd
    var subdir_cwd = try tmp_dir.openDir(io, denormed_something_subdir_wtf8, .{});
    defer subdir_cwd.close(io);

    try renameExe(tmp_dir, io, "something/goodbye.exe", "hello.exe");
    try std.process.setCurrentDir(io, subdir_cwd);

    // clear the PATH again
    std.debug.assert(SetEnvironmentVariableW(utf16Literal("PATH"), null).toBool());

    // while we're at it make sure non-windows separators work fine
    try testExec(gpa, io, "../hello", "hello from exe\n");
}

fn testExecError(err: anyerror, gpa: Allocator, io: Io, command: []const u8) !void {
    return std.testing.expectError(err, testExec(gpa, io, command, ""));
}

fn testExec(gpa: Allocator, io: Io, command: []const u8, expected_stdout: []const u8) !void {
    return testExecWithCwdInner(gpa, io, command, .inherit, expected_stdout);
}

fn testExecWithCwd(gpa: Allocator, io: Io, command: []const u8, cwd: []const u8, expected_stdout: []const u8) !void {
    // Test by passing CWD as both a path and a Dir
    try testExecWithCwdInner(gpa, io, command, .{ .path = cwd }, expected_stdout);

    var cwd_dir = try Io.Dir.cwd().openDir(io, cwd, .{});
    defer cwd_dir.close(io);

    try testExecWithCwdInner(gpa, io, command, .{ .dir = cwd_dir }, expected_stdout);
}

fn testExecWithCwdInner(gpa: Allocator, io: Io, command: []const u8, cwd: std.process.Child.Cwd, expected_stdout: []const u8) !void {
    const result = try std.process.run(gpa, io, .{
        .argv = &[_][]const u8{command},
        .cwd = cwd,
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    try std.testing.expectEqualStrings("", result.stderr);
    try std.testing.expectEqualStrings(expected_stdout, result.stdout);
}

fn renameExe(dir: Io.Dir, io: Io, old_sub_path: []const u8, new_sub_path: []const u8) !void {
    var attempt: u5 = 10;
    while (true) break dir.rename(old_sub_path, dir, new_sub_path, io) catch |err| switch (err) {
        error.AccessDenied => {
            if (attempt == 26) return error.AccessDenied;
            // give the kernel a chance to finish closing the executable handle
            const interval = @as(std.os.windows.LARGE_INTEGER, -1) << attempt;
            _ = std.os.windows.ntdll.NtDelayExecution(.FALSE, &interval);
            attempt += 1;
            continue;
        },
        else => |e| return e,
    };
}

pub extern "kernel32" fn SetEnvironmentVariableW(
    lpName: windows.LPCWSTR,
    lpValue: ?windows.LPCWSTR,
) callconv(.winapi) windows.BOOL;
