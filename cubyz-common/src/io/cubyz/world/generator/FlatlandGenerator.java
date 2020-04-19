package io.cubyz.world.generator;

import org.joml.Vector3i;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.blocks.BlockInstance;
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
					BlockInstance bi = null;
					if (y == 2) {
						bi = new BlockInstance(grass);
					}
					if (y == 1) {
						bi = new BlockInstance(dirt);
					}
					if (y == 0) {
						bi = new BlockInstance(bedrock);
					}
					bi.setPosition(new Vector3i(chunk.getX() * 16 + px, y, chunk.getZ() * 16 + pz));
					chunk.rawAddBlock(px, y, pz, bi);
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
