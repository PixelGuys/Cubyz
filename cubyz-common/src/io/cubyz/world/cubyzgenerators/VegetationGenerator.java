package io.cubyz.world.cubyzgenerators;

import java.util.Random;

import io.cubyz.api.CubyzRegistries;
import io.cubyz.blocks.Block;
import io.cubyz.world.Noise;
import io.cubyz.world.World;

public class VegetationGenerator implements FancyGenerator {
	@Override
	public int getPriority() {
		return 131072; // Comes somewhere after cave generation.
	}

	@Override
	public void generate(long seed, int cx, int cy, Block[][][] chunk, float[][] heatMap, int[][] heightMap) {
		int wx = cx << 4;
		int wy = cy << 4;
		
		float[][] vegetationMap = Noise.generateMapFragment(wx-8, wy-8, 32, 32, 128, seed + 3*(seed + 1 & Integer.MAX_VALUE));
		// Go through all positions in this and ±½ chunks to determine if there is a tree and if yes generate it.
		Random rand = new Random(seed);
		long l1 = rand.nextLong();
		long l2 = rand.nextLong();
		for(int px = 0; px < 32; px++) {
			for(int py = 0; py < 32; py++) {
				float value = vegetationMap[px][py];
				float temperature = heatMap[px][py];
				if(heightMap[px][py] >= TerrainGenerator.SEA_LEVEL + 4) {
					// if (value < 0) value = 0;
					rand.setSeed(seed^l1*(px+wx-8)^l2*(py+wy-8));
					generateVegetation(chunk, px - 8, py - 8, heightMap[px][py] + 1, value, temperature, rand);
				}
			}
		}
	}
	
	
	// Serves to map the vegetation*10+x value to a chance for spawning that vegetation
	private static int [] vegMap = {8192, 4096, 2048, 1024, 512, 256, 142, 122, 104, 88, 74, 62, 52, 44, 38, 34, 32};
	
	private static void generateVegetation(Block[][][] ch, int x, int y, int h, float vegetation, float temperature, Random rand) {
		if(temperature < 30 && vegetation > 0.4F && rand.nextInt(vegMap[(int)(vegetation*5)+6]) == 0) {
			generateTree(ch, x, y, h, rand.nextInt(3)+7);
		} else if(temperature > 40 && rand.nextInt(vegMap[(int)(vegetation*10)]) == 0) {
			generateCactus(ch, x, y, h, rand.nextInt(3)+3);
		}
	}
	
	private static void generateTree(Block[][][] ch, int x, int y, int h, int height) {
		//Instances
		Block wood = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:oak_log");
		Block leaves = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:oak_leaves");
		
		//Position of the first block of wood
		if(x >= 0 && x < 16 && y >= 0 && y < 16) {
			for (int i = 0; i < height; i++) {
				if (y + i < World.WORLD_HEIGHT) {
					if(ch[x][y][h+i] != null && (!ch[x][y][h+i].isDegradable() || wood.isDegradable())) {
						continue;
					}
					ch[x][y][h+i] = wood;
				}
			}
		}
		
		//Position of the first block of leaves
		height = 3 * height >> 1;
		for (int i = height / 3; i < height; i++) {
			int j = (height - i) >> 1;
			for (int k = 1 - j; k < j; k++) {
				for (int l = 1 - j; l < j; l++) {
					if (y + i < World.WORLD_HEIGHT && x+k >= 0 && x+k < 16 && y+l >= 0 && y+l < 16) {
						if(ch[x+k][y+l][h+i] != null && (!ch[x+k][y+l][h+i].isDegradable() || leaves.isDegradable())) {
							continue;
						}
						ch[x+k][y+l][h+i] = leaves;
					}
				}
			}
		}
	}
	
	private static void generateCactus(Block[][][] ch, int x, int y, int h, int height) {
		//Instances
		Block cactus = CubyzRegistries.BLOCK_REGISTRY.getByID("cubyz:cactus");
		
		//Position of the first block of cactus
		if(x >= 0 && x < 15 && y >= 0 && y < 15) {
			for (int i = 0; i < height; i++) {
				if (y + i < World.WORLD_HEIGHT) {
					if(ch[x][y][h+i] != null && (!ch[x][y][h+i].isDegradable() || cactus.isDegradable())) {
						continue;
					}
					ch[x][y][h + i] = cactus;
				}
			}
		}
	}

}
