package io.cubyz.world;

import io.cubyz.api.CubzRegistries;
import io.cubyz.blocks.*;

public class Structures {
	// Serves to map the vegetation*10+x value to a chance for spawning that vegetation
	private static int [] vegMap = {16383, 8191, 4095, 2047, 1023, 511, 255, 127, 127, 63, 63, 63, 31, 31, 31, 31, 31};
	
	public static void generateVegetation(Chunk ch, int x, int y, int z, float vegetation, float temperature, int rand) {
		if(temperature < 40 && vegetation > 0.4F && (rand&vegMap[(int)(vegetation*5)+6]) == 1) {
			generateTree(ch, x, y, z, (rand/1000&3));
		} else if(temperature > 40 && (rand&vegMap[(int)(vegetation*10)]) == 1) {
			generateCactus(ch, x, y, z, (rand/1000&3));
		}
	}
	
	public static void generateTree(Chunk ch, int x, int y, int z, int height) {
		//Instances
		Block wood = CubzRegistries.BLOCK_REGISTRY.getByID("cubyz:oak_log");
		Block leaves = CubzRegistries.BLOCK_REGISTRY.getByID("cubyz:oak_leaves");
		
		//Position of the first block of wood
		height += 7;
		for (int i = 0; i < height; i++) {
			if (y + i < World.WORLD_HEIGHT) {
				ch.addBlock(wood, x, y + i, z);
			}
		}
		
		//Position of the first block of leaves
		height = 3 * height >> 1;
		for (int i = height / 3; i < height; i++) {
			int j = (height - i) >> 1;
			for (int k = 1 - j; k < j; k++) {
				for (int l = 1 - j; l < j; l++) {
					if (y + i < World.WORLD_HEIGHT) {
						ch.addBlock(leaves, x + k, y + i, z + l);
					}
				}
			}
		}
	}
	
	public static void generateCactus(Chunk ch, int x, int y, int z, int height) {
		//Instances
		Block cactus = CubzRegistries.BLOCK_REGISTRY.getByID("cubyz:cactus");
		
		//Position of the first block of wood
		height += 3;
		for (int i = 0; i < height; i++) {
			if (y + i < World.WORLD_HEIGHT) {
				ch.addBlock(cactus, x, y + i, z);
			}
		}
	}
}