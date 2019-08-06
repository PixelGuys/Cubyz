package io.cubyz.blocks;

import io.cubyz.items.Item;

public class EmeraldOre extends Ore {

	public EmeraldOre() {
		setTexture("emerald_ore");
		setID("cubyz:emerald_ore");
		setHeight(25);
		setChance(0.001F);
		Item bd = new Item();
		bd.setID("cubyz_items:emerald");
		bd.setTexture("materials/emerald.png");
		setBlockDrop(bd);
	}
	
}