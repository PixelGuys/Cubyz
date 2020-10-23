package io.cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import io.cubyz.blocks.Block;
import io.cubyz.world.Chunk;
import io.cubyz.world.ReducedChunk;

/**
 * Stores the vertical structure of a biome from top to bottom.<br>
 */

public class BlockStructure {
	private final BlockStack[] structure;
	public BlockStructure(BlockStack ... blocks) {
		structure = blocks;
	}
	public int addSubTerranian(Chunk chunk, int depth, int x, int z, int highResDepth, Random rand) {
		int startingDepth = depth;
		for(int i = 0; i < structure.length; i++) {
			for(int j = 0; j < structure[i].min; j++) {
				byte data = structure[i].block.mode.getNaturalStandard();
				if(i == 0 && j == 0 && structure[i].block.mode.getRegistryID().toString().equals("cubyz:stackable")) {
					data = (byte)highResDepth;
				}
				chunk.rawAddBlock(x, depth--, z, structure[i].block, data);
				if(depth <= 0) return depth;
			}
			int variation = rand.nextInt(1 + structure[i].max - structure[i].min);
			for(int j = 0; j < variation; j++) {
				chunk.rawAddBlock(x, depth--, z, structure[i].block);
				if(depth <= 0) return depth;
			}
		}
		if(depth == startingDepth) return depth;
		return depth + 1;
	}
	
	/**
	 * A version for reduced chunks.
	 * @param chunk
	 * @param depth
	 * @param x
	 * @param z
	 * @return new y coordinate
	 */
	public int addSubTerranian(ReducedChunk chunk, int depth, int xz) {
		int startingDepth = depth;
		for(int i = 0; i < structure.length; i++) {
			// Only do the non-random part. No one is going to care about the exact block placement here.
			// Choose a minimum of 1 block per layer to compensate for losses from rightshifting and not considering the random part.
			for(int j = 0; j <= structure[i].min >>> chunk.resolutionShift; j++) {
				chunk.blocks[xz | (depth-- << 2*(chunk.widthShift - chunk.resolutionShift))] = structure[i].block.color;
				if(depth <= 0) return depth;
			}
		}
		if(depth == startingDepth) return depth;
		return depth + 1;
	}
	
	public static class BlockStack {
		private final Block block;
		private final int min;
		private final int max;
		public BlockStack(Block block, int min, int max) {
			this.block = block;
			this.min = min;
			this.max = max;
		}
	}
}
