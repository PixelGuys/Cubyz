package io.cubyz.blocks;

import io.cubyz.items.Item;

public class CoalOre extends Ore {

	public CoalOre() {
		setID("cubyz:coal_ore");
		height = 128;
		spawns = 20;
		maxLength = 8;
		maxSize = 2.9F;
		setHardness(40);
		Item bd = new Item();
		bd.setID("cubyz:coal");
		bd.setTexture("materials/coal.png");
		setBlockDrop(bd);
	}
	
}