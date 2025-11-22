const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;


list: main.ListUnmanaged(Vec3i) = .{},
mutex: std.Thread.Mutex = .{},

pub fn init() @This() {
	return .{};
}
pub fn deinit(self: *@This()) void {
	self.mutex = undefined;
	self.list.deinit(main.globalAllocator);
}
pub fn add(self: *@This(), position: Vec3i) void {
	self.mutex.lock();
	defer self.mutex.unlock();
	self.list.append(main.globalAllocator, position);
}
pub fn update(self: *@This(), ch: *main.chunk.ServerChunk) void {
	// swap
	self.mutex.lock();
	const list = self.list;
	defer list.deinit(main.globalAllocator);
	self.list = .{};
	self.mutex.unlock();

	// handle events
	for(list.items) |event| {
		const x = event[0] & main.chunk.chunkMask;
		const y = event[1] & main.chunk.chunkMask;
		const z = event[2] & main.chunk.chunkMask;

		ch.mutex.lock();
		const block = ch.getBlock(x, y, z);
		ch.mutex.unlock();

		_ = block.onUpdate().run(.{
			.block = block,
			.chunk = ch,
			.x = x,
			.y = y,
			.z = z,
		});
	}
}
