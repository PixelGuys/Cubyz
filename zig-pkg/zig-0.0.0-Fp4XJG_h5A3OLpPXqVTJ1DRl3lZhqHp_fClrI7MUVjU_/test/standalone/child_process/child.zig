const std = @import("std");
const Io = std.Io;

// 42 is expected by parent; other values result in test failure
var exit_code: u8 = 42;

pub fn main(init: std.process.Init) !void {
    try run(init.arena.allocator(), init.io, init.minimal.args);
    std.process.exit(exit_code);
}

fn run(arena: std.mem.Allocator, io: Io, args: std.process.Args) !void {
    var it = try args.iterateAllocator(arena);
    defer it.deinit();
    _ = it.next() orelse unreachable; // skip binary name

    // test cmd args
    const hello_arg = "hello arg";
    const a1 = it.next() orelse unreachable;
    if (!std.mem.eql(u8, a1, hello_arg)) {
        testError(io, "first arg: '{s}'; want '{s}'", .{ a1, hello_arg });
    }
    if (it.next()) |a2| {
        testError(io, "expected only one arg; got more: {s}", .{a2});
    }

    // test stdout pipe; parent verifies
    try std.Io.File.stdout().writeStreamingAll(io, "hello from stdout");

    // test stdin pipe from parent
    const hello_stdin = "hello from stdin";
    var buf: [hello_stdin.len]u8 = undefined;
    const stdin: std.Io.File = .stdin();
    var reader = stdin.reader(io, &.{});
    const n = try reader.interface.readSliceShort(&buf);
    if (!std.mem.eql(u8, buf[0..n], hello_stdin)) {
        testError(io, "stdin: '{s}'; want '{s}'", .{ buf[0..n], hello_stdin });
    }
}

fn testError(io: Io, comptime fmt: []const u8, args: anytype) void {
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;
    stderr.print("CHILD TEST ERROR: ", .{}) catch {};
    stderr.print(fmt, args) catch {};
    if (fmt[fmt.len - 1] != '\n') {
        stderr.writeByte('\n') catch {};
    }
    exit_code = 1;
}
