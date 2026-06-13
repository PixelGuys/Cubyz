const std = @import("std");
const Atomic = std.atomic.Value;

const main = @import("main");

const StdinHandler = @This();

thread: std.Thread = undefined,
threadId: std.Thread.Id = undefined,
running: Atomic(bool) = .init(true),
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

	result.thread = try std.Thread.spawn(.{}, run, .{result});
	result.thread.setName(main.io, "Stdin Thread") catch |err| std.log.err("Couldn't rename thread: {s}", .{@errorName(err)});
	return result;
}

pub fn deinit(self: *StdinHandler) void {
	self.running.store(false, .monotonic);
	self.thread.join();
	main.globalAllocator.destroy(self);
}

pub fn run(self: *StdinHandler) void {
	self.threadId = std.Thread.getCurrentId();
	main.initThreadLocals();
	defer main.deinitThreadLocals();

	while (self.running.load(.monotonic)) {
		main.heap.GarbageCollection.syncPoint();
		const input = self.reader.interface.takeDelimiterExclusive('\n') catch |err| {
			std.log.err("Reading from stdin failed closing stdin. err: {t}", .{err});
			self.running.store(false, .monotonic);
			break;
		};
		self.reader.interface.toss(1);
		std.debug.print("input: {s}\n", .{input});
	}
}
