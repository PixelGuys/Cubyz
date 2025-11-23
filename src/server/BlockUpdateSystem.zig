const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const BlockPosition = struct {x: u5, y: u5, z: u5};
list: main.ListUnmanaged(BlockPosition) = .{},
mutex: std.Thread.Mutex = .{},

pub fn init() @This() {
	return .{};
}
pub fn deinit(self: *@This()) void {
	self.mutex = undefined;
	self.list.deinit(main.globalAllocator);
}
pub fn add(self: *@This(), position: BlockPosition) void {
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
		ch.mutex.lock();
		const block = ch.getBlock(event.x, event.y, event.z);
		ch.mutex.unlock();

		_ = block.onUpdate().run(.{
			.block = block,
			.chunk = ch,
			.x = event.x,
			.y = event.y,
			.z = event.z,
		});
	}
}
