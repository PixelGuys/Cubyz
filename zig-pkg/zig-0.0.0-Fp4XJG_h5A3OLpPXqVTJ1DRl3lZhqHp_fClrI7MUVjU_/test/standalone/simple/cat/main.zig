const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const warn = std.log.warn;
const fatal = std.process.fatal;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    const exe = args[0];
    var catted_anything = false;
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &.{});

    const cwd = Io.Dir.cwd();

    for (args[1..]) |arg| {
        if (mem.eql(u8, arg, "-")) {
            catted_anything = true;
            _ = try stdout.sendFileAll(&stdin_reader, .unlimited);
            try stdout.flush();
        } else if (mem.startsWith(u8, arg, "-")) {
            return usage(exe);
        } else {
            const file = cwd.openFile(io, arg, .{}) catch |err| fatal("unable to open file: {t}\n", .{err});
            defer file.close(io);

            catted_anything = true;
            var file_reader = file.reader(io, &.{});
            _ = try stdout.sendFileAll(&file_reader, .unlimited);
            try stdout.flush();
        }
    }
    if (!catted_anything) {
        _ = try stdout.sendFileAll(&stdin_reader, .unlimited);
        try stdout.flush();
    }
}

fn usage(exe: []const u8) !void {
    warn("Usage: {s} [FILE]...\n", .{exe});
    return error.Invalid;
}
