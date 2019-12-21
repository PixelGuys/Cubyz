package io.cubyz.blocks;

import io.cubyz.items.Item;

public class GoldOre extends Ore {

	public GoldOre() {
		setID("cubyz:gold_ore");
		height = 32;
		spawns = 2;
		maxLength = 3;
		maxSize = 2.0F;
		setHardness(45);
		Item bd = new Item();
		bd.setID("cubyz:gold_ore");
		bd.setTexture("materials/gold_ore.png");
		setBlockDrop(bd);
	}
	
}