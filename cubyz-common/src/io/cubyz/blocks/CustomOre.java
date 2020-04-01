package io.cubyz.blocks;

import java.util.Random;

public class CustomOre extends Ore {

	private int color;
	
	public static CustomOre random(long seed) {
		Random rnd = new Random(seed);
		CustomOre ore = new CustomOre();
		ore.color = rnd.nextInt(0xFFFFFF);
		ore.height = rnd.nextInt(160);
		ore.spawns = rnd.nextInt(10);
		ore.maxLength = rnd.nextInt(10);
		ore.maxSize = rnd.nextInt(5);
		return ore;
	}
	
}
