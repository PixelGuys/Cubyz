const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");

var readBuffer: [1024]u8 = undefined;

var running: bool = false;

pub fn init() void {
	if (builtin.os.tag == .windows) {
		std.log.warn("Console per stdin is currently not supported on windows", .{});
		running = false;
	} else {
		running = true;
	}
}

pub fn deinit() void {
	running = false;
}

pub fn update() void {
	if (!running) return;
	const _result = main.io.operateTimeout(.{.file_read_streaming = .{
		.data = &.{&readBuffer},
		.file = std.Io.File.stdin(),
	}}, .{.duration = .{.raw = .zero, .clock = .awake}}) catch |err| {
		if (err == error.Timeout) return;
		std.log.err("Error while reading from stdin: {t}", .{err});
		running = false;
		return;
	};
	const result = _result.file_read_streaming catch |err| {
		std.log.err("Error while reading from stdin: {t}", .{err});
		running = false;
		return;
	};
	if (result == 0) return;
	if (readBuffer[0] == '/') {
		main.server.command.execute(readBuffer[1 .. result - 1], .server);
	} else {
		main.server.sendMessage("<Server> {s}", .{readBuffer[0 .. result - 1]});
	}
}
