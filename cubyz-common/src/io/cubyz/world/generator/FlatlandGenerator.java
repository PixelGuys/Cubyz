package io.cubyz.world.generator;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.world.Chunk;
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
	public void generate(Chunk chunk, Surface surface) {
		for (int px = 0; px < 16; px++) {
			for (int pz = 0; pz < 16; pz++) {
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
					chunk.rawAddBlock(px, y, pz, b, (byte)0);
				}
			}
		}
		chunk.applyBlockChanges();
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "flatland");
	}

}
