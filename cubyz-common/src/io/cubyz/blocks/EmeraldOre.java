package io.cubyz.blocks;

import io.cubyz.items.Item;

public class EmeraldOre extends Ore {

	public EmeraldOre() {
		setID("cubyz:emerald_ore");
		height = 24;
		spawns = 1;
		maxLength = 0.6f;
		maxSize = 0.1F;
		setHardness(55);
		Item bd = new Item();
		bd.setID("cubyz:emerald");
		bd.setTexture("materials/emerald.png");
		setBlockDrop(bd);
	}
	
}