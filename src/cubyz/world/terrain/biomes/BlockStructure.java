package cubyz.world.terrain.biomes;

import java.util.Random;

import cubyz.world.Chunk;
import cubyz.world.blocks.Blocks;

/**
 * Stores the vertical ground structure of a biome from top to bottom.<br>
 */

public class BlockStructure {
	private final BlockStack[] structure;
	public BlockStructure(BlockStack ... blocks) {
		structure = blocks;
	}
	public BlockStructure(String ... blocks) {
		structure = new BlockStack[blocks.length];
		for(int i = 0; i < blocks.length; i++) {
			String[] parts = blocks[i].trim().split("\\s+");
			int min = 1;
			int max = 1;
			String blockString = parts[0];
			if (parts.length == 2) {
				min = max = Integer.parseInt(parts[0]);
				blockString = parts[1];
			} else if (parts.length == 4 && parts[1].equalsIgnoreCase("to")) {
				min = Integer.parseInt(parts[0]);
				max = Integer.parseInt(parts[2]);
				blockString = parts[3];
			}
			int block = Blocks.getByID(blockString);
			structure[i] = new BlockStructure.BlockStack(block, min, max);
		}
	}
	
	public int addSubTerranian(Chunk chunk, int depth, int x, int z, int highResDepth, Random rand) {
		int startingDepth = depth;
		for(int i = 0; i < structure.length; i++) {
			int total = structure[i].min + rand.nextInt(1 + structure[i].max - structure[i].min);
			for(int j = 0; j < total; j++) {
				int block = structure[i].block;
				block = Blocks.mode(block).getNaturalStandard(block);
				if (i == 0 && j == 0 && Blocks.mode(block).getRegistryID().toString().equals("cubyz:stackable")) {
					block = (block & Blocks.TYPE_MASK) | (highResDepth << 16);
				}
				if (chunk.liesInChunk(x, depth - chunk.wy, z)) {
					chunk.updateBlockInGeneration(x, depth - chunk.wy, z, block);
				}
				depth -= chunk.voxelSize;
			}
		}
		if (depth == startingDepth) return depth;
		return depth;
	}
	
	public static class BlockStack {
		private final int block;
		private final int min;
		private final int max;
		public BlockStack(int block, int min, int max) {
			this.block = block;
			this.min = min;
			this.max = max;
		}
	}
}
