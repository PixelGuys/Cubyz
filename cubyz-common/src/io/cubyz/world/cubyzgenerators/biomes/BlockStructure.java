package io.cubyz.world.cubyzgenerators.biomes;

import io.cubyz.blocks.Block;

// Stores the vertical structure of a biome from top to bottom.
// TODO: Randomly variable structure(like top-block is either ice or snow, or there are 4-7 sand blocks on top).

public class BlockStructure {
	private Block[] structure;
	public BlockStructure(Block ... blocks) {
		structure = blocks;
	}
	public Block getSubterranian(int depth, int x, int y) {
		// TODO: Use x and y as seed for random structure.
		if(depth < structure.length) {
			return structure[depth];
		}
		return null;
	}
}
