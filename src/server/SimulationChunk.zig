const std = @import("std");

const main = @import("main");
const ChunkPosition = main.chunk.ChunkPosition;
const ServerChunk = main.chunk.ServerChunk;
const BlockUpdateSystem = main.server.BlockUpdateSystem;

const SimulationChunk = @This();

chunk: std.atomic.Value(?*ServerChunk) = .init(null),
refCount: std.atomic.Value(u32),
pos: ChunkPosition,
blockUpdateSystem: BlockUpdateSystem,

pub fn initAndIncreaseRefCount(pos: ChunkPosition) *SimulationChunk {
	const self = main.globalAllocator.create(SimulationChunk);
	self.* = .{
		.refCount = .init(1),
		.pos = pos,
		.blockUpdateSystem = .init(),
	};
	return self;
}

fn deinit(self: *SimulationChunk) void {
	std.debug.assert(self.refCount.load(.monotonic) == 0);
	self.blockUpdateSystem.deinit();
	if(self.chunk.raw) |ch| ch.decreaseRefCount();
	main.globalAllocator.destroy(self);
}

pub fn increaseRefCount(self: *SimulationChunk) void {
	const prevVal = self.refCount.fetchAdd(1, .monotonic);
	std.debug.assert(prevVal != 0);
}

pub fn decreaseRefCount(self: *SimulationChunk) void {
	const prevVal = self.refCount.fetchSub(1, .monotonic);
	std.debug.assert(prevVal != 0);
	if(prevVal == 2) {
		main.server.world_zig.ChunkManager.tryRemoveSimulationChunk(self);
	}
	if(prevVal == 1) {
		self.deinit();
	}
}

pub fn getChunk(self: *SimulationChunk) ?*ServerChunk {
	return self.chunk.load(.acquire);
}

pub fn setChunkAndDecreaseRefCount(self: *SimulationChunk, ch: *ServerChunk) void {
	std.debug.assert(self.chunk.swap(ch, .release) == null);
}

pub fn update(self: *SimulationChunk, randomTickSpeed: u32) void {
	const serverChunk = self.getChunk() orelse return;
	tickBlocksInChunk(serverChunk, randomTickSpeed);
	self.blockUpdateSystem.update(serverChunk);
}

fn tickBlocksInChunk(_chunk: *ServerChunk, randomTickSpeed: u32) void {
	for(0..randomTickSpeed) |_| {
		const blockIndex: i32 = main.random.nextInt(i32, &main.seed);

		const x: i32 = blockIndex >> main.chunk.chunkShift2 & main.chunk.chunkMask;
		const y: i32 = blockIndex >> main.chunk.chunkShift & main.chunk.chunkMask;
		const z: i32 = blockIndex & main.chunk.chunkMask;

		_chunk.mutex.lock();
		const block = _chunk.getBlock(x, y, z);
		_chunk.mutex.unlock();
		_ = block.onTick().run(.{.block = block, .chunk = _chunk, .x = x, .y = y, .z = z});
	}
}
