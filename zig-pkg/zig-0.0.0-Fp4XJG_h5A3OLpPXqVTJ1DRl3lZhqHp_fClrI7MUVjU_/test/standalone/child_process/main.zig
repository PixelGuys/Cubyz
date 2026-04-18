const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init.Minimal) !void {
    // make sure safety checks are enabled even in release modes
    var gpa_state: std.heap.DebugAllocator(.{ .safety = true }) = .{};
    defer if (gpa_state.deinit() != .ok) {
        @panic("found memory leaks");
    };
    const gpa = gpa_state.allocator();

    var threaded: Io.Threaded = .init(gpa, .{
        .argv0 = .init(init.args),
        .environ = init.environ,
    });
    defer threaded.deinit();
    const io = threaded.io();

    const process_cwd_path = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(process_cwd_path);

    var environ_map = try init.environ.createMap(gpa);
    defer environ_map.deinit();

    var it = try init.args.iterateAllocator(gpa);
    defer it.deinit();
    _ = it.next() orelse unreachable; // skip binary name
    const child_path, const needs_free = child_path: {
        const child_path = it.next() orelse unreachable;
        const cwd_path = it.next() orelse break :child_path .{ child_path, false };
        // If there is a third argument, it is the current CWD somewhere within the cache directory.
        // In that case, modify the child path in order to test spawning a path with a leading `..` component.
        break :child_path .{ try std.fs.path.relative(gpa, process_cwd_path, &environ_map, cwd_path, child_path), true };
    };
    defer if (needs_free) gpa.free(child_path);

    var child = try std.process.spawn(io, .{
        .argv = &.{ child_path, "hello arg" },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .inherit,
    });

    const child_stdin = child.stdin.?;
    try child_stdin.writeStreamingAll(io, "hello from stdin"); // verified in child
    child_stdin.close(io);
    child.stdin = null;

    const hello_stdout = "hello from stdout";
    var buf: [hello_stdout.len]u8 = undefined;
    var stdout_reader = child.stdout.?.readerStreaming(io, &.{});
    const n = try stdout_reader.interface.readSliceShort(&buf);
    if (!std.mem.eql(u8, buf[0..n], hello_stdout)) {
        testError(io, "child stdout: '{s}'; want '{s}'", .{ buf[0..n], hello_stdout });
    }

    switch (try child.wait(io)) {
        .exited => |code| {
            const child_ok_code = 42; // set by child if no test errors
            if (code != child_ok_code) {
                testError(io, "child exit code: {d}; want {d}", .{ code, child_ok_code });
            }
        },
        else => |term| testError(io, "abnormal child exit: {}", .{term}),
    }
    if (parent_test_error) return error.ParentTestError;

    // Check that FileNotFound is consistent across platforms when trying to spawn an executable that doesn't exist
    const missing_child_path = try std.mem.concat(gpa, u8, &.{ child_path, "_intentionally_missing" });
    defer gpa.free(missing_child_path);
    try std.testing.expectError(error.FileNotFound, std.process.run(gpa, io, .{ .argv = &.{missing_child_path} }));
}

var parent_test_error = false;

fn testError(io: Io, comptime fmt: []const u8, args: anytype) void {
    var stderr_writer = Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;
    stderr.print("PARENT TEST ERROR: ", .{}) catch {};
    stderr.print(fmt, args) catch {};
    if (fmt[fmt.len - 1] != '\n') {
        stderr.writeByte('\n') catch {};
    }
    parent_test_error = true;
}
