const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // Test cases are from https://github.com/rust-lang/rust/blob/master/tests/ui/std/windows-bat-args.rs
    try testExecError(error.InvalidBatchScriptArg, gpa, io, &.{"\x00"});
    try testExecError(error.InvalidBatchScriptArg, gpa, io, &.{"\n"});
    try testExecError(error.InvalidBatchScriptArg, gpa, io, &.{"\r"});
    try testExec(gpa, io, &.{ "a", "b" }, null);
    try testExec(gpa, io, &.{ "c is for cat", "d is for dog" }, null);
    try testExec(gpa, io, &.{ "\"", " \"" }, null);
    try testExec(gpa, io, &.{ "\\", "\\" }, null);
    try testExec(gpa, io, &.{">file.txt"}, null);
    try testExec(gpa, io, &.{"whoami.exe"}, null);
    try testExec(gpa, io, &.{"&a.exe"}, null);
    try testExec(gpa, io, &.{"&echo hello "}, null);
    try testExec(gpa, io, &.{ "&echo hello", "&whoami", ">file.txt" }, null);
    try testExec(gpa, io, &.{"!TMP!"}, null);
    try testExec(gpa, io, &.{"key=value"}, null);
    try testExec(gpa, io, &.{"\"key=value\""}, null);
    try testExec(gpa, io, &.{"key = value"}, null);
    try testExec(gpa, io, &.{"key=[\"value\"]"}, null);
    try testExec(gpa, io, &.{ "", "a=b" }, null);
    try testExec(gpa, io, &.{"key=\"foo bar\""}, null);
    try testExec(gpa, io, &.{"key=[\"my_value]"}, null);
    try testExec(gpa, io, &.{"key=[\"my_value\",\"other-value\"]"}, null);
    try testExec(gpa, io, &.{"key\\=value"}, null);
    try testExec(gpa, io, &.{"key=\"&whoami\""}, null);
    try testExec(gpa, io, &.{"key=\"value\"=5"}, null);
    try testExec(gpa, io, &.{"key=[\">file.txt\"]"}, null);
    try testExec(gpa, io, &.{"%hello"}, null);
    try testExec(gpa, io, &.{"%PATH%"}, null);
    try testExec(gpa, io, &.{"%%cd:~,%"}, null);
    try testExec(gpa, io, &.{"%PATH%PATH%"}, null);
    try testExec(gpa, io, &.{"\">file.txt"}, null);
    try testExec(gpa, io, &.{"abc\"&echo hello"}, null);
    try testExec(gpa, io, &.{"123\">file.txt"}, null);
    try testExec(gpa, io, &.{"\"&echo hello&whoami.exe"}, null);
    try testExec(gpa, io, &.{ "\"hello^\"world\"", "hello &echo oh no >file.txt" }, null);
    try testExec(gpa, io, &.{"&whoami.exe"}, null);

    // Ensure that trailing space and . characters can't lead to unexpected bat/cmd script execution.
    // In many Windows APIs (including CreateProcess), trailing space and . characters are stripped
    // from paths, so if a path with trailing . and space character(s) is passed directly to
    // CreateProcess, then it could end up executing a batch/cmd script that naive extension detection
    // would not flag as .bat/.cmd.
    //
    // Note that we expect an error here, though, which *is* a valid mitigation, but also an implementation detail.
    // This error is caused by the use of a wildcard with NtQueryDirectoryFile to optimize PATHEXT searching. That is,
    // the trailing characters in the app name will lead to a FileNotFound error as the wildcard-appended path will not
    // match any real paths on the filesystem (e.g. `foo.bat .. *` will not match `foo.bat`; only `foo.bat*` will).
    //
    // This being an error matches the behavior of running a command via the command line of cmd.exe, too:
    //
    //     > "args1.bat .. "
    //     '"args1.bat .. "' is not recognized as an internal or external command,
    //     operable program or batch file.
    try std.testing.expectError(error.FileNotFound, testExecBat(gpa, io, "args1.bat .. ", &.{"abc"}, null));
    const absolute_with_trailing = blk: {
        const absolute_path = try Io.Dir.cwd().realPathFileAlloc(io, "args1.bat", gpa);
        defer gpa.free(absolute_path);
        break :blk try std.mem.concat(gpa, u8, &.{ absolute_path, " .. " });
    };
    defer gpa.free(absolute_with_trailing);
    try std.testing.expectError(error.FileNotFound, testExecBat(gpa, io, absolute_with_trailing, &.{"abc"}, null));

    var env = env: {
        var env = try init.environ_map.clone(gpa);
        errdefer env.deinit();
        // No escaping
        try env.put("FOO", "123");
        // Some possible escaping of %FOO% that could be expanded
        // when escaping cmd.exe meta characters with ^
        try env.put("FOO^", "123"); // only escaping %
        try env.put("^F^O^O^", "123"); // escaping every char
        break :env env;
    };
    defer env.deinit();
    try testExec(gpa, io, &.{"%FOO%"}, &env);

    // Ensure that none of the `>file.txt`s have caused file.txt to be created
    try std.testing.expectError(error.FileNotFound, Io.Dir.cwd().access(io, "file.txt", .{}));
}

fn testExecError(err: anyerror, gpa: Allocator, io: Io, args: []const []const u8) !void {
    return std.testing.expectError(err, testExec(gpa, io, args, null));
}

fn testExec(gpa: Allocator, io: Io, args: []const []const u8, env: ?*std.process.Environ.Map) !void {
    try testExecBat(gpa, io, "args1.bat", args, env);
    try testExecBat(gpa, io, "args2.bat", args, env);
    try testExecBat(gpa, io, "args3.bat", args, env);
}

fn testExecBat(gpa: Allocator, io: Io, bat: []const u8, args: []const []const u8, env: ?*std.process.Environ.Map) !void {
    const argv = try gpa.alloc([]const u8, 1 + args.len);
    defer gpa.free(argv);
    argv[0] = bat;
    @memcpy(argv[1..], args);

    const can_have_trailing_empty_args = std.mem.eql(u8, bat, "args3.bat");

    const result = try std.process.run(gpa, io, .{
        .environ_map = env,
        .argv = argv,
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    try std.testing.expectEqualStrings("", result.stderr);
    var it = std.mem.splitScalar(u8, result.stdout, '\x00');
    var i: usize = 0;
    while (it.next()) |actual_arg| {
        if (i >= args.len and can_have_trailing_empty_args) {
            try std.testing.expectEqualStrings("", actual_arg);
            continue;
        }
        const expected_arg = args[i];
        try std.testing.expectEqualStrings(expected_arg, actual_arg);
        i += 1;
    }
}
