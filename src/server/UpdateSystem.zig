const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const BlockUpdate = struct {
	position: Vec3i,
	callTimeTick: u64,

	fn compare(_: void, a: BlockUpdate, b: BlockUpdate) std.math.Order {
		if(a.callTimeTick < b.callTimeTick)
			return .lt;
		if(a.callTimeTick > b.callTimeTick)
			return .gt;
		return .eq;
	}
};

pub const UpdateSystem = struct {
	queue: std.PriorityQueue(BlockUpdate, void, BlockUpdate.compare),
	currentTick: u64 = 0,

	pub fn init() *UpdateSystem {
		const self = main.globalAllocator.create(UpdateSystem);
		errdefer main.globalAllocator.destroy(self);
		self.* = UpdateSystem{
			.queue = .init(main.globalAllocator.allocator, void{}),
		};
		return self;
	}
	pub fn deinit(self: *UpdateSystem) void {
		self.queue.deinit();
		main.globalAllocator.destroy(self);
	}
	pub fn add(self: *UpdateSystem, position: Vec3i, inTicks: u32) void {
		self.queue.add(BlockUpdate{.position = position, .callTimeTick = self.currentTick + inTicks}) catch unreachable;
	}
	pub fn update(self: *UpdateSystem, world: *main.server.ServerWorld) void {
		const currentTick = self.currentTick;
		self.currentTick += 1;

		while(true) {
			// is this event for this tick?
			if(self.queue.peek()) |event| {
				if(event.callTimeTick > currentTick)
					break;
			}
			// does the event even exist?
			if(self.queue.removeOrNull()) |event| {
				var ch = world.getOrGenerateChunkAndIncreaseRefCount(main.chunk.ChunkPosition.initFromWorldPos(event.position, 1));
				defer ch.decreaseRefCount();
				if(world.getBlock(event.position[0], event.position[1], event.position[2])) |block| {
					_ = block.onUpdate().run(.{
						.block = block,
						.chunk = ch,
						.x = event.position[0] & main.chunk.chunkMask,
						.y = event.position[1] & main.chunk.chunkMask,
						.z = event.position[2] & main.chunk.chunkMask,
					});
				}
			} else break;
		}
	}
};
