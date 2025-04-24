const std = @import("std");

const main = @import("main");
const blocks = main.blocks;
const chunk = main.chunk;
const utils = main.utils;

const ZonElement = main.ZonElement;
const Vec3i = main.vec.Vec3i;

pub const BlockTick = struct {
	pub fn add(wldPos: Vec3i, _chunk: *chunk.Chunk, block: blocks.Block) void {
		const blockIndex = _chunk.getLocalBlockIndex(wldPos);
		const blockData = block.toInt();

		_chunk.blockPosToTickableBlockMutex.lock();
		_chunk.blockPosToTickableBlockMap.putNoClobber(main.globalAllocator.allocator, blockIndex, blockData) catch unreachable;
		_chunk.blockPosToTickableBlockMutex.unlock();
	}

	pub fn remove(wldPos: Vec3i, _chunk: *chunk.Chunk) void {
		const blockIndex = _chunk.getLocalBlockIndex(wldPos);

		_chunk.blockPosToTickableBlockMutex.lock();
		const blockData = _chunk.blockPosToTickableBlockMap.fetchRemove(blockIndex);
		_chunk.blockPosToTickableBlockMutex.unlock();

		_ = blockData orelse {
			std.log.err("Could not remove TickEvent at position {}", .{wldPos});
		};
	}
};
