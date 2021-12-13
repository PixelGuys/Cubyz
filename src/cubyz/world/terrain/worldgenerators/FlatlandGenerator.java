package cubyz.world.terrain.worldgenerators;

import cubyz.api.Resource;
import cubyz.world.Chunk;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.Blocks;

/**
 * Simple generator that does flat worlds with 3 layers.
 * 1. Grass
 * 2. Dirt
 * 3. Bedrock
 */

public class FlatlandGenerator extends SurfaceGenerator {

	private static int grass = Blocks.getByID("cubyz:grass");
	private static int soil = Blocks.getByID("cubyz:soil");
	
	@Override
	public void generate(Chunk chunk, ServerWorld world) {
		for (int x = 0; x < chunk.getWidth(); x += chunk.getVoxelSize()) {
			for (int z = 0; z < chunk.getWidth(); z += chunk.getVoxelSize()) {
				for (int y = 0; y < chunk.getWidth(); y += chunk.getVoxelSize()) {
					int wy = y + chunk.getWorldY();
					if (wy > 0) continue;
					int b = 0;
					if (wy == 0) {
						b = grass;
					} else {
						b = soil;
					}
					chunk.updateBlockInGeneration(x, y, z, b);
				}
			}
		}
	}

	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "flatland");
	}

}
