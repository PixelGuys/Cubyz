//! Accepts a stack trace in a file (whose path is given as argv[1]), and removes all
//! non-reproducible information from it, including addresses, module names, and file
//! paths. All module names are removed, file paths become just their basename, and
//! addresses are replaced with a fixed string. So, lines like this:
//!
//!   /something/foo.zig:1:5: 0x12345678 in bar (main.o)
//!       doThing();
//!              ^
//!   ???:?:?: 0x12345678 in qux (other.o)
//!   ???:?:?: 0x12345678 in ??? (???)
//!
//! ...are turned into lines like this:
//!
//!   foo.zig:1:5: [address] in bar
//!       doThing();
//!              ^
//!   ???:?:?: [address] in qux
//!   ???:?:?: [address] in ???
//!
//! Additionally, lines reporting unwind errors are removed:
//!
//!   Unwind error at address `/proc/self/exe:0x1016533` (unwind info unavailable), remaining frames may be incorrect
//!   Cannot print stack trace: safe unwind unavilable for target
//!
//! With these transformations, the test harness can safely do string comparisons.

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len != 2) std.process.fatal("usage: convert-stack-trace path/to/test/output", .{});

    var read_buf: [1024]u8 = undefined;
    var write_buf: [1024]u8 = undefined;

    const in_file = try std.Io.Dir.cwd().openFile(io, args[1], .{});
    defer in_file.close(io);

    const out_file: std.Io.File = .stdout();

    var in_fr = in_file.reader(io, &read_buf);
    var out_fw = out_file.writer(io, &write_buf);

    const w = &out_fw.interface;

    while (in_fr.interface.takeDelimiterInclusive('\n')) |in_line| {
        if (std.mem.eql(u8, in_line, "Cannot print stack trace: safe unwind unavailable for target\n") or
            std.mem.startsWith(u8, in_line, "Unwind error at address `"))
        {
            // Remove these lines from the output.
            continue;
        }

        const src_pos_end = std.mem.indexOf(u8, in_line, ": 0x") orelse {
            try w.writeAll(in_line);
            continue;
        };
        const src_pos_start = b: {
            const postfix = ".zig:";
            const postfix_index = std.mem.lastIndexOf(u8, in_line[0..src_pos_end], postfix) orelse {
                try w.writeAll(in_line);
                continue;
            };
            break :b postfix_index + postfix.len;
        };

        const addr_end = std.mem.findPos(u8, in_line, src_pos_end, " in ") orelse {
            try w.writeAll(in_line);
            continue;
        };
        const symbol_end = std.mem.findPos(u8, in_line, addr_end, " (") orelse {
            try w.writeAll(in_line);
            continue;
        };
        if (!std.mem.endsWith(u8, std.mem.trimEnd(u8, in_line, "\n"), ")")) {
            try w.writeAll(in_line);
            continue;
        }

        // Where '_' is a placeholder for an arbitrary string, we now know the line looks like:
        //
        //   _:_:_: 0x_ in _ (_)
        //
        // That seems good enough to assume it's a stack trace frame! We'll rewrite it to:
        //
        //   _:_:_: [address] in _
        //
        // ...with that first '_' being replaced by its basename.

        const src_path = in_line[0..src_pos_start];
        const basename_start = if (std.mem.lastIndexOfAny(u8, src_path, "/\\")) |i| i + 1 else 0;
        const symbol_start = addr_end + " in ".len;
        try w.writeAll(in_line[basename_start..src_pos_end]);
        try w.writeAll(": [address] in ");
        try w.writeAll(in_line[symbol_start..symbol_end]);
        try w.writeByte('\n');
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }

    try w.flush();
}

const std = @import("std");
