const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");

var readBuffer: [10000]u8 = undefined;

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
	const result = readFromStdin();
	if (result == 0) return;
	if (result == readBuffer.len) {
		std.log.warn("Input exceeded 10000 character limit", .{});
		while (readFromStdin() != 0) {}
		return;
	}
	if (readBuffer[0] == '/') {
		main.server.command.execute(readBuffer[1 .. result - 1], .server);
	} else {
		main.server.sendMessage("<Server> {s}", .{readBuffer[0 .. result - 1]});
	}
}

fn readFromStdin() usize {
	const _result = main.io.operateTimeout(.{.file_read_streaming = .{
		.data = &.{&readBuffer},
		.file = std.Io.File.stdin(),
	}}, .{.duration = .{.raw = .zero, .clock = .awake}}) catch |err| {
		if (err == error.Timeout) return 0;
		std.log.err("Error while reading from stdin: {t}", .{err});
		running = false;
		return 0;
	};
	return _result.file_read_streaming catch |err| {
		std.log.err("Error while reading from stdin: {t}", .{err});
		running = false;
		return 0;
	};
}
