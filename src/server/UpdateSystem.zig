const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const UpdateSystem = struct {
	queue: main.utils.CircularBufferQueue(Vec3i),

	pub fn init() UpdateSystem {
		return .{
			.queue = .init(main.globalAllocator, 32),
		};
	}
	pub fn deinit(self: UpdateSystem) void {
		self.queue.deinit();
	}
	pub fn add(self: *UpdateSystem, position: Vec3i) void {
		self.queue.pushBack(position);
	}
	pub fn update(self: *UpdateSystem, world: *main.server.ServerWorld) void {
		// event queue
		const amountToUpdate = self.queue.len;
		for(0..amountToUpdate) |_| {
			if(self.queue.popFront()) |event| {
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
	}
};
