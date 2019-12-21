package io.cubyz.blocks;

import io.cubyz.items.Item;

public class DiamondOre extends Ore {

	public DiamondOre() {
		setID("cubyz:diamond_ore");
		height = 16;
		spawns = 1;
		maxLength = 2;
		maxSize = 0.5F;
		setHardness(80);
		Item bd = new Item();
		bd.setID("cubyz:diamond");
		bd.setTexture("materials/diamond.png");
		setBlockDrop(bd);
	}
	
}