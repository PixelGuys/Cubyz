const std = @import("std");

const main = @import("main");
const ChunkPosition = main.chunk.ChunkPosition;
const ServerChunk = main.chunk.ServerChunk;
const BlockUpdateSystem = main.server.BlockUpdateSystem;

const SimulationChunk = @This();

chunk: std.atomic.Value(?*ServerChunk) = .init(null),
pos: ChunkPosition,
blockUpdateSystem: BlockUpdateSystem,

pub fn init(pos: ChunkPosition) *SimulationChunk {
	const self = main.globalAllocator.create(SimulationChunk);
	self.* = .{
		.pos = pos,
		.blockUpdateSystem = .init(),
	};
	return self;
}

fn privateDeinit(self: *SimulationChunk) void {
	self.blockUpdateSystem.deinit();
	main.globalAllocator.destroy(self);
}

pub fn deferredDeinit(self: *SimulationChunk) void {
	main.heap.GarbageCollection.deferredFree(.{.ptr = self, .freeFunction = main.meta.castFunctionSelfToAnyopaquep(privateDeinit)});
}

pub fn getChunk(self: *SimulationChunk) ?*ServerChunk {
	return self.chunk.load(.acquire);
}

pub fn setChunk(self: *SimulationChunk, ch: *ServerChunk) void {
	std.debug.assert(self.chunk.swap(ch, .release) == null);
}

pub fn update(self: *SimulationChunk, randomTickSpeed: u32) void {
	const serverChunk = self.getChunk() orelse return;
	tickBlocksInChunk(serverChunk, randomTickSpeed);
	self.blockUpdateSystem.update(serverChunk);
}

fn tickBlocksInChunk(_chunk: *ServerChunk, randomTickSpeed: u32) void {
	for (0..randomTickSpeed) |_| {
		const blockIndex = main.random.nextInt(u15, &main.seed);
		const pos = main.chunk.BlockPos.fromIndex(blockIndex);

		_chunk.mutex.lock();
		const block = _chunk.getBlock(pos.x, pos.y, pos.z);
		_chunk.mutex.unlock();
		_ = block.onTick().run(.{.block = block, .chunk = _chunk, .blockPos = pos});
	}
}
