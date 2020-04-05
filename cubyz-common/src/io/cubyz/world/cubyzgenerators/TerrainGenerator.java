package io.cubyz.world.cubyzgenerators;

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
	
	private static Block grass = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:grass");
	private static Block snow = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:snow");
	private static Block ice = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:ice");
	private static Block stone = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:stone");
	private static Block bedrock = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:bedrock");

	// Liquid
	public static final int SEA_LEVEL = 100;
	private static Block water = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:water");

	@Override
	public void generate(long seed, int cx, int cy, Block[][][] chunk, float[][] heatMap, int[][] heightMap, Biome[][] biomeMap) {
		for(int px = 0; px < 16; px++) {
			for(int py = 0; py < 16; py++) {
				int y = heightMap[px+8][py+8];
				float temperature = heatMap[px+8][py+8];
				for(int j = y > SEA_LEVEL ? Math.min(y, World.WORLD_HEIGHT-1) : SEA_LEVEL; j >= 0; j--) {
					int depth = y-j;
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
						} else {
							b = biomeMap[px+8][py+8].struct.getSubterranian(depth, px, py);
							if(b == null) {
								b = stone;
							}
							if(temperature < 0 && b == grass) {
								b = snow;
							}
						}
					}
					chunk[px][py][j] = b;
				}
			}
		}
	}
}
