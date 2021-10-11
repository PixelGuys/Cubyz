package cubyz.world.terrain.generators;

import java.util.Random;

import cubyz.api.CubyzRegistries;
import cubyz.api.Resource;
import cubyz.world.Chunk;
import cubyz.world.ServerWorld;
import cubyz.world.blocks.Block;
import cubyz.world.terrain.MapFragment;
import cubyz.world.terrain.biomes.Biome;

/**
 * Generates the basic terrain(stone, dirt, sand, ...).
 */

public class TerrainGenerator implements Generator {
	
	@Override
	public int getPriority() {
		return 1024; // Within Cubyz the first to be executed, but mods might want to come before that for whatever reason.
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_terrain");
	}
	
	private static Block ice = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:ice");
	private static Block stone = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:stone");

	// Liquid
	private static Block water = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:water");

	@Override
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, MapFragment map, ServerWorld world) {
		Random rand = new Random(seed);
		int seedX = rand.nextInt() | 1;
		int seedZ = rand.nextInt() | 1;
		for(int x = 0; x < chunk.getWidth(); x += chunk.getVoxelSize()) {
			for(int z = 0; z < chunk.getWidth(); z += chunk.getVoxelSize()) {
				int y = chunk.startIndex((int)map.getHeight(wx + x, wz + z) - chunk.getVoxelSize() + 1);
				int yOff = 1 + (int)((map.getHeight(wx + x, wz + z) - y)*16);
				int startY = y > 0 ? y : 0;
				startY = chunk.startIndex(Math.min(startY, wy + chunk.getWidth() - chunk.getVoxelSize()));
				int endY = wy;
				int j = startY;
				// Add water between 0 and the terrain height:
				for(; j >= Math.max(y+1, endY); j -= chunk.getVoxelSize()) {
					if(map.getBiome(wx + x, wz + z).type == Biome.Type.ARCTIC_OCEAN && j == 0) {
						chunk.updateBlock(x, j - wy, z, ice);
					} else {
						chunk.updateBlock(x, j - wy, z, water);
					}
				}
				// Add the biomes surface structure:
				if(j <= y) {
					rand.setSeed((seedX*(wx + x) << 32) ^ seedZ*(wz + z));
					j = Math.min(map.getBiome(wx + x, wz + z).struct.addSubTerranian(chunk, y, x, z, yOff, rand), j);
				}
				// Add the underground:
				for(; j >= endY; j -= chunk.getVoxelSize()) {
					chunk.updateBlock(x, j - wy, z, stone);
				}
			}
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0x65c7f9fdc0641f94L;
	}
}
