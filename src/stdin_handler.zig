const std = @import("std");

const main = @import("main");

var stdin: std.Io.File = undefined;
var readBuffer: [1024]u8 = undefined;

var running: bool = true;

pub fn init() void {
	stdin = .stdin();
}

pub fn deinit() void {
	running = false;
}

pub fn update() void {
	if (!running) return;
	const _result = main.io.operateTimeout(.{.file_read_streaming = .{
		.data = &.{&readBuffer},
		.file = stdin,
	}}, .{.duration = .{.raw = .fromMilliseconds(1), .clock = .awake}}) catch |err| {
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
	main.server.sendMessage("<Server> {s}", .{readBuffer[0 .. result - 1]});
}
