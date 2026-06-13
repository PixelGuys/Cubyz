const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");

const StdinHandler = @This();

future: std.Io.Future(void) = undefined,
stdin: std.Io.File,
reader: std.Io.File.Reader = undefined,
buffer: [1024]u8 = undefined,

pub fn init() !*StdinHandler {
	const result: *StdinHandler = main.globalAllocator.create(StdinHandler);
	errdefer main.globalAllocator.destroy(result);
	result.* = .{
		.stdin = .stdin(),
	};
	result.reader = result.stdin.reader(main.io, &result.buffer);

	result.future = try main.io.concurrent(run, .{result});
	return result;
}

pub fn deinit(self: *StdinHandler) void {
	self.future.cancel(main.io);
	main.globalAllocator.destroy(self);
}

pub fn run(self: *StdinHandler) void {
	main.initThreadLocals();
	defer main.deinitThreadLocals();

	while (true) {
		const input = self.reader.interface.takeDelimiterExclusive('\n') catch {
			if (self.reader.err.? == error.Canceled) break;
			std.log.err("Reading from stdin failed. Closing stdin. err: {t}", .{self.reader.err.?});
			break;
		};
		self.reader.interface.toss(1);
		main.server.sendMessage("{s}", .{input});
	}
}
