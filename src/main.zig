const std = @import("std");

var logFile: std.fs.File = undefined;

pub fn log(
	comptime level: std.log.Level,
	comptime scope: @Type(.EnumLiteral),
	comptime format: []const u8,
	args: anytype,
) void {
	if(scope != .default) {
		@compileError("Scopes are not supported.");
	}
	const color = comptime switch (level) {
		std.log.Level.err => "\x1b[31m",
		std.log.Level.info => "",
		std.log.Level.warn => "\x1b[33m",
		std.log.Level.debug => "\x1b[37;44m",
	};
	var buf: [4096]u8 = undefined;

	std.debug.getStderrMutex().lock();
	defer std.debug.getStderrMutex().unlock();

	const fileMessage = std.fmt.bufPrint(&buf, "[" ++ level.asText() ++ "]" ++ ": " ++ format ++ "\n", args) catch return;
	logFile.writeAll(fileMessage) catch return;

	const terminalMessage = std.fmt.bufPrint(&buf, color ++ format ++ "\x1b[0m\n", args) catch return;
	nosuspend std.io.getStdErr().writeAll(terminalMessage) catch return;
}

pub fn main() !void {
	logFile = std.fs.cwd().createFile("logs/latest.log", .{}) catch unreachable; // init logging.

	std.log.info("Hello zig.", .{});
}
