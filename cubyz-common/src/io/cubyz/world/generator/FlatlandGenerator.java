package io.cubyz.world.generator;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.world.NormalChunk;
import io.cubyz.world.ReducedChunk;
import io.cubyz.world.Surface;

/**
 * Simple generator that does flat worlds with 3 layers.
 * 1. Grass
 * 2. Dirt
 * 3. Bedrock
 */

public class FlatlandGenerator extends SurfaceGenerator {

	private static Block grass = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:grass");
	private static Block dirt = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:dirt");
	private static Block bedrock = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:bedrock");
	
	@Override
	public void generate(NormalChunk chunk, Surface surface) {
		for (int x = 0; x < 16; x++) {
			for (int z = 0; z < 16; z++) {
				for (int y = 0; y < 3; y++) {
					Block b = null;
					if (y == 2) {
						b = grass;
					}
					if (y == 1) {
						b = dirt;
					}
					if (y == 0) {
						b = bedrock;
					}
					chunk.updateBlock(x, y, z, b);
				}
			}
		}
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "flatland");
	}

	@Override
	public void generate(ReducedChunk chunk, Surface surface) {
		for (int x = 0; x < 16 >>> chunk.resolutionShift; x++) {
			for (int z = 0; z < 16 >>> chunk.resolutionShift; z++) {
				for (int y = 0; y <= 2 >>> chunk.resolutionShift; y++) {
					Block block = null;
					if (y == 2 >>> chunk.resolutionShift) {
						block = grass;
					}
					else if (y == 1) {
						block = dirt;
					}
					else if (y == 0) {
						block = bedrock;
					}
					chunk.blocks[(x << (4 - chunk.resolutionShift)) | (y << (8 - 2*chunk.resolutionShift) | z)] = block;
				}
			}
		}
		chunk.applyBlockChanges();
	}

}
