const std = @import("std");
const builtin = @import("builtin");

const main = @import("main");

var readBuffer: [100_000]u8 = undefined;

var running: bool = true;

pub fn update() void {
	if (!running) return;
	if (builtin.os.tag == .windows) {
		std.log.warn("Console per stdin is currently not supported on windows", .{});
		running = false;
		return;
	}
	const result = readFromStdin();
	if (result == readBuffer.len) {
		std.log.warn("Input exceeded {} character limit", .{readBuffer.len});
		while (readFromStdin() != 0) {}
		return;
	}
	const msg = std.mem.trim(u8, readBuffer[0..result], "\n");
	if (msg.len == 0) return;
	if (!std.unicode.utf8ValidateSlice(msg)) {
		std.log.err("Server message contains invalid UTF-8 characters.", .{});
		return;
	}
	if (msg[0] == '/') {
		main.server.command.execute(msg[1..], .server);
	} else {
		main.server.sendMessage("<Server> {s}", .{msg});
	}
}

fn readFromStdin() usize {
	const result = main.io.operateTimeout(.{.file_read_streaming = .{
		.data = &.{&readBuffer},
		.file = std.Io.File.stdin(),
	}}, .{.duration = .{.raw = .zero, .clock = .awake}}) catch |err| {
		if (err == error.Timeout) return 0;
		std.log.err("Error while reading from stdin: {t}", .{err});
		running = false;
		return 0;
	};
	return result.file_read_streaming catch |err| {
		std.log.err("Error while reading from stdin: {t}", .{err});
		running = false;
		return 0;
	};
}
