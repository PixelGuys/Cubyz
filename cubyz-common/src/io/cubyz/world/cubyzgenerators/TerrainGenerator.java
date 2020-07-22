package io.cubyz.world.cubyzgenerators;

import java.util.Random;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;
import io.cubyz.world.World;
import io.cubyz.world.cubyzgenerators.biomes.Biome;

public class TerrainGenerator implements FancyGenerator {
	
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
	public void generate(long seed, int cx, int cz, Block[][][] chunk, boolean[][] vegetationIgnoreMap, float[][] heatMap, int[][] heightMap, Biome[][] biomeMap, int worldSize) {
		Random rand = new Random(seed);
		int seedX = rand.nextInt() | 1;
		int seedZ = rand.nextInt() | 1;
		for(int px = 0; px < 16; px++) {
			for(int pz = 0; pz < 16; pz++) {
				int y = heightMap[px+8][pz+8];
				float temperature = heatMap[px+8][pz+8];
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
							rand.setSeed((seedX*((cx << 4) + px) << 32) ^ seedZ*((cz << 4) + pz));
							j = biomeMap[px+8][pz+8].struct.addSubTerranian(chunk, j, px, pz, rand);
							continue;
						} else {
							b = stone;
						}
					}
					chunk[px][pz][j] = b;
				}
			}
		}
	}
}
