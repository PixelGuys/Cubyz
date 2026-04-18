const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &.{});
    const out = &stdout_writer.interface;

    var line_buffer: [20]u8 = undefined;
    var stdin_reader: std.Io.File.Reader = .init(.stdin(), init.io, &line_buffer);
    const in = &stdin_reader.interface;

    try out.writeAll("Welcome to the Guess Number Game in Zig.\n");

    var rng: std.Random.IoSource = .{ .io = init.io };
    const answer = rng.interface().intRangeLessThan(u8, 0, 100) + 1;

    while (true) {
        try out.writeAll("\nGuess a number between 1 and 100: ");
        const untrimmed_line = in.takeSentinel('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                try out.writeAll("Line too long.\n");
                _ = try in.discardDelimiterInclusive('\n');
                continue;
            },
            else => |e| return e,
        };
        const line = std.mem.trimEnd(u8, untrimmed_line, "\r\n");

        const guess = std.fmt.parseUnsigned(u8, line, 10) catch {
            try out.writeAll("Invalid number.\n");
            continue;
        };
        if (guess > answer) {
            try out.writeAll("Guess lower.\n");
        } else if (guess < answer) {
            try out.writeAll("Guess higher.\n");
        } else {
            try out.writeAll("You win!\n");
            return;
        }
    }
}
