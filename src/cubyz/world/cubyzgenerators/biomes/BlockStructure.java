package cubyz.world.cubyzgenerators.biomes;

import java.util.Random;

import cubyz.world.Chunk;
import cubyz.world.blocks.Block;

/**
 * Stores the vertical ground structure of a biome from top to bottom.<br>
 */

public class BlockStructure {
	private final BlockStack[] structure;
	public BlockStructure(BlockStack ... blocks) {
		structure = blocks;
	}
	
	public int addSubTerranian(Chunk chunk, int depth, int x, int z, int highResDepth, Random rand) {
		int startingDepth = depth;
		for(int i = 0; i < structure.length; i++) {
			int total = structure[i].min + rand.nextInt(1 + structure[i].max - structure[i].min);
			for(int j = 0; j < total; j++) {
				byte data = structure[i].block.mode.getNaturalStandard();
				if(i == 0 && j == 0 && structure[i].block.mode.getRegistryID().toString().equals("cubyz:stackable")) {
					data = (byte)highResDepth;
				}
				if(chunk.liesInChunk(x, depth - chunk.getWorldY(), z)) {
					chunk.updateBlock(x, depth - chunk.getWorldY(), z, structure[i].block, data);
				}
				depth -= chunk.getVoxelSize();
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
