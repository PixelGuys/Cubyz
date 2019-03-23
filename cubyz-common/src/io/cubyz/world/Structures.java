package io.cubyz.world;

import io.cubyz.api.CubzRegistries;
import io.cubyz.blocks.*;
import io.cubyz.modding.ModLoader;
import io.cubyz.world.*;

import java.util.Random;

import org.joml.*;

public class Structures {
	
	private static Random random = new Random();
	
	public static void generateTree(Chunk ch, int x, int y, int z) {
		//Instances
		Block wood = CubzRegistries.BLOCK_REGISTRY.getByID("cubyz:oak_log");
		Block leaves = CubzRegistries.BLOCK_REGISTRY.getByID("cubyz:oak_leaves");
		
		//Position of the first block of wood
		int height = 7 + random.nextInt(5);
		for (int i = 0; i < height; i++) {
			ch.addBlock(wood, x, y + i, z);
		}
		
		//Position of the first block of leaves
		height = 3 * height >> 1;
		for (int i = height / 3; i < height; i++) {
			int j = (height - i) >> 1;
			for (int k = 1 - j; k < j; k++) {
				for (int l = 1 - j; l < j; l++) {
					ch.addBlock(leaves, x + k, y + i, z + l);
				}
			}
		}
	}	
}