package cubyz.world.terrain.generators;

import java.util.Random;

import cubyz.api.CurrentWorldRegistries;
import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.world.Chunk;
import cubyz.world.ChunkManager;
import cubyz.world.blocks.Blocks;
import cubyz.world.terrain.MapFragment;
import cubyz.world.terrain.biomes.Biome;

/**
 * Generates the basic terrain(stone, dirt, sand, ...).
 */

public class TerrainGenerator implements Generator {
	
	private int ice;
	private int stone;

	private int water;

	@Override
	public void init(JsonObject parameters, CurrentWorldRegistries registries) {
		water = Blocks.getByID("cubyz:water");
		ice = Blocks.getByID("cubyz:ice");
		stone = Blocks.getByID("cubyz:stone");
	}
	
	@Override
	public int getPriority() {
		return 1024; // Within Cubyz the first to be executed, but mods might want to come before that for whatever reason.
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_terrain");
	}

	@Override
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, MapFragment map, ChunkManager generator) {
		Random rand = new Random(seed);
		int seedX = rand.nextInt() | 1;
		int seedZ = rand.nextInt() | 1;
		for(int x = 0; x < chunk.getWidth(); x += chunk.voxelSize) {
			for(int z = 0; z < chunk.getWidth(); z += chunk.voxelSize) {
				int y = chunk.startIndex((int)map.getHeight(wx + x, wz + z) - chunk.voxelSize + 1);
				int yOff = 1 + (int)((map.getHeight(wx + x, wz + z) - y)*16);
				int startY = y > 0 ? y : 0;
				startY = chunk.startIndex(Math.min(startY, wy + chunk.getWidth() - chunk.voxelSize));
				int endY = wy;
				int j = startY;
				// Add water between 0 and the terrain height:
				for(; j >= Math.max(y+1, endY); j -= chunk.voxelSize) {
					if (map.getBiome(wx + x, wz + z).type == Biome.Type.ARCTIC_OCEAN && j == 0) {
						chunk.updateBlockInGeneration(x, j - wy, z, ice);
					} else {
						chunk.updateBlockInGeneration(x, j - wy, z, water);
					}
				}
				// Add the biomes surface structure:
				if (j <= y) {
					rand.setSeed((seedX*(wx + x) << 32) ^ seedZ*(wz + z));
					j = Math.min(map.getBiome(wx + x, wz + z).struct.addSubTerranian(chunk, y, x, z, yOff, rand), j);
				}
				// Add the underground:
				for(; j >= endY; j -= chunk.voxelSize) {
					chunk.updateBlockInGeneration(x, j - wy, z, stone);
				}
			}
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0x65c7f9fdc0641f94L;
	}
}
