package io.cubyz.world.cubyzgenerators;

import java.util.Random;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.world.MetaChunk;
import io.cubyz.world.ReducedChunk;
import io.cubyz.world.Surface;
import io.cubyz.world.World;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

public class TerrainGenerator implements FancyGenerator, ReducedGenerator {
	
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
	private static Block bedrock = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:bedrock");

	// Liquid
	public static final int SEA_LEVEL = 100;
	private static Block water = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:water");

	@Override
	public void generate(long seed, int cx, int cz, Block[][][] chunk, boolean[][] vegetationIgnoreMap, float[][] heatMap, float[][] heightMap, Biome[][] biomeMap, byte[][][] blockData, int worldSize) {
		Random rand = new Random(seed);
		int seedX = rand.nextInt() | 1;
		int seedZ = rand.nextInt() | 1;
		for(int x = 0; x < 16; x++) {
			for(int z = 0; z < 16; z++) {
				int y = (int)heightMap[x+8][z+8];
				int yOff = 1 + (int)((heightMap[x+8][z+8]-y)*16);
				float temperature = heatMap[x+8][z+8];
				for(int j = y > SEA_LEVEL ? Math.min(y, World.WORLD_HEIGHT-1) : SEA_LEVEL; j >= 0; j--) {
					Block b = null;
					if(j > y) {
						if(temperature <= 0 && j == SEA_LEVEL) {
							b = ice;
						} else {
							b = water;
						}
					} else {
						if(j == 0) {
							b = bedrock;
						} else if(j == y) {
							rand.setSeed((seedX*((cx << 4) + x) << 32) ^ seedZ*((cz << 4) + z));
							j = biomeMap[x+8][z+8].struct.addSubTerranian(chunk, blockData, j, x, z, yOff, rand);
							continue;
						} else {
							b = stone;
						}
					}
					chunk[x][z][j] = b;
				}
			}
		}
	}

	@Override
	public void generate(long seed, int wx, int wz, ReducedChunk chunk, MetaChunk containingMetaChunk, Surface surface) {
		for(int x = 0; x < 16 >>> chunk.resolution; x++) {
			for(int z = 0; z < 16 >>> chunk.resolution; z++) {
				int y = (int)(containingMetaChunk.heightMap[(wx + (x << chunk.resolution)) & 255][(wz + (z << chunk.resolution)) & 255]*(World.WORLD_HEIGHT >>> chunk.resolution));
				float temperature = containingMetaChunk.heatMap[(wx + (x << chunk.resolution)) & 255][(wz + (z << chunk.resolution)) & 255];
				for(int j = y > (SEA_LEVEL >>> chunk.resolution) ? Math.min(y, (World.WORLD_HEIGHT >>> chunk.resolution) - 1) : SEA_LEVEL >>> chunk.resolution; j >= 0; j--) {
					short color = 0;
					if(j > y) {
						if(temperature <= 0 && j == SEA_LEVEL) {
							color = ice.color;
						} else {
							color = water.color;
						}
					} else {
						if(j == 0 && y >>> chunk.resolution != 0) {
							color = bedrock.color;
						} else if(j == y) {
							containingMetaChunk.biomeMap[(wx + (x << chunk.resolution)) & 255][(wz + (z << chunk.resolution)) & 255].struct.addSubTerranian(chunk, j, (x << (4 - chunk.resolution) | z));
							continue;
						} else {
							color = stone.color;
						}
					}
					chunk.blocks[(x << (4 - chunk.resolution)) | (j << (8 - 2*chunk.resolution)) | z] = color;
				}
			}
		}
	}

	@Override
	public long getGeneratorSeed() {
		return 0x65c7f9fdc0641f94L;
	}
}
