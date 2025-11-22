const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const UpdateSystem = struct {
	list: main.ListUnmanaged(Vec3i) = .{},
	mutex: std.Thread.Mutex = .{},

	pub fn init() UpdateSystem {
		return .{};
	}
	pub fn deinit(self: *UpdateSystem) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		self.list.deinit(main.globalAllocator);
	}
	pub fn add(self: *UpdateSystem, position: Vec3i) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		self.list.append(main.globalAllocator, position);
	}
	pub fn update(self: *UpdateSystem, world: *main.server.ServerWorld) void {
		// swap
		self.mutex.lock();
		const list = self.list;
		defer list.deinit(main.globalAllocator);
		self.list = .{};
		self.mutex.unlock();

		// handle events
		for(list.items) |event| {
			var ch = world.getChunkFromCacheAndIncreaseRefCount(main.chunk.ChunkPosition.initFromWorldPos(event, 1)) orelse continue;
			defer ch.decreaseRefCount();
			if(world.getBlock(event[0], event[1], event[2])) |block| {
				_ = block.onUpdate().run(.{
					.block = block,
					.chunk = ch,
					.x = event[0] & main.chunk.chunkMask,
					.y = event[1] & main.chunk.chunkMask,
					.z = event[2] & main.chunk.chunkMask,
				});
			}
		}
	}
};
