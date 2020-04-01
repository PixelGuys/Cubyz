package io.cubyz.blocks;

import java.util.Random;

public class CustomOre extends Ore {

	private int color;
	
	public static CustomOre random(Random rand) {
		CustomOre ore = new CustomOre();
		ore.color = rand.nextInt(0xFFFFFF);
		ore.height = rand.nextInt(160);
		ore.spawns = rand.nextInt(20);
		ore.maxLength = rand.nextInt(10);
		ore.maxSize = rand.nextInt(5);
		// TODO: Add texture generation.
		return ore;
	}
	
}
