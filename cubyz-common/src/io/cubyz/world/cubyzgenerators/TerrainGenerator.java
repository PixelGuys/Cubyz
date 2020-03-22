package io.cubyz.world.cubyzgenerators;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.api.Registry;
import io.cubyz.api.Resource;
import io.cubyz.blocks.Block;

public class TerrainGenerator implements FancyGenerator {
	
	@Override
	public int getPriority() {
		return 1024; // Within Cubyz the first to be executed, but mods might want to come before that for whatever reason.
	}
	
	@Override
	public Resource getRegistryID() {
		return new Resource("cubyz", "lifeland_terrain");
	}
	
	private static Registry<Block> br = CubyzRegistries.BLOCK_REGISTRY; // shortcut to BLOCK_REGISTRY
	private static Block grass = br.getByID("cubyz:grass");
	private static Block sand = br.getByID("cubyz:sand");
	private static Block snow = br.getByID("cubyz:snow");
	private static Block dirt = br.getByID("cubyz:dirt");
	private static Block ice = br.getByID("cubyz:ice");
	private static Block stone = br.getByID("cubyz:stone");
	private static Block bedrock = br.getByID("cubyz:bedrock");

	// Liquid
	public static final int SEA_LEVEL = 100;
	private static Block water = br.getByID("cubyz:water");

	@Override
	public void generate(long seed, int cx, int cy, Block[][][] chunk, float[][] heatMap, int[][] heightMap) {
		//int height = chunk[0][0].length;

		for(int px = 0; px < 16; px++) {
			for(int py = 0; py < 16; py++) {
				int y = heightMap[px+8][py+8];
				float temperature = heatMap[px+8][py+8];
				for(int j = y > SEA_LEVEL ? y : SEA_LEVEL; j >= 0; j--) {
					Block b = null;
					if(j > y) {
						if(temperature <= 0 && j == SEA_LEVEL) {
							b = ice;
						} else {
							b = water;
						}
					} else if(((y < SEA_LEVEL + 4 && temperature > 5) || temperature > 40 || y < SEA_LEVEL)
							&& j > y - 3) {
						b = sand;
					} else if(j == y) {
						if(temperature > 0) {
							b = grass;
						} else {
							b = snow;
						}
					} else if(j > y - 3) {
						b = dirt;
					} else if(j > 0) {
						b = stone;
					} else {
						b = bedrock;
					}
					chunk[px][py][j] = b;
				}
			}
		}
	}
}
