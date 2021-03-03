package io.cubyz.world.cubyzgenerators;

import java.util.Random;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.world.Chunk;
import io.cubyz.world.Region;
import io.cubyz.world.Surface;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

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
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, Region containingRegion, Surface surface, boolean[][] vegetationIgnoreMap) {
		this.generate(seed, wx, wy, wz, chunk, containingRegion, surface);
	}
	
	public void generate(long seed, int wx, int wy, int wz, Chunk chunk, Region containingRegion, Surface surface) {
		Random rand = new Random(seed);
		int seedX = rand.nextInt() | 1;
		int seedZ = rand.nextInt() | 1;
		for(int x = 0; x < chunk.getWidth(); x += chunk.getVoxelSize()) {
			for(int z = 0; z < chunk.getWidth(); z += chunk.getVoxelSize()) {
				int y = chunk.startIndex((int)containingRegion.heightMap[wx+x & 255][wz+z & 255] - chunk.getVoxelSize() + 1);
				int yOff = 1 + (int)((containingRegion.heightMap[wx+x & 255][wz+z & 255] - y)*16);
				int startY = y > 0 ? y : 0;
				int endY = chunk.getWorldY();
				for(int j = startY; j >= endY; j--) {
					Block b = null;
					if(j > y) {
						if(containingRegion.biomeMap[wx+x & 255][wz+z & 255].type == Biome.Type.ARCTIC_OCEAN && j == 0) {
							b = ice;
						} else {
							b = water;
						}
					} else {
						if(j == y) {
							rand.setSeed((seedX*(wx + x) << 32) ^ seedZ*(wz + z));
							j = containingRegion.biomeMap[wx+x & 255][wz+z & 255].struct.addSubTerranian(chunk, j, x, z, yOff, rand);
							continue;
						} else {
							b = stone;
						}
					}
					if(!chunk.liesInChunk(x, j - chunk.getWorldY(), z)) continue;
					chunk.updateBlock(x, j - chunk.getWorldY(), z, b);
				}
			}
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0x65c7f9fdc0641f94L;
	}
}
