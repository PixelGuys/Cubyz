const main = @import("main");
const Block = main.blocks.Block;
const Neighbor = main.chunk.Neighbor;

pub fn init() void {}
pub fn deinit() void {}
pub fn reset() void {}

// MARK: non-interface fns

pub fn updateBlockFromNeighborConnectivity(block: *Block, neighborSupportive: [6]bool) void {
	if (!neighborSupportive[Neighbor.dirDown.toInt()]) block.* = .air;
}
