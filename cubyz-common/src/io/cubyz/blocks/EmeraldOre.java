package io.cubyz.blocks;

import io.cubyz.items.Item;

public class EmeraldOre extends Ore {

	public EmeraldOre() {
		setID("cubyz:emerald_ore");
		setHeight(25);
		setChance(0.001F);
		setHardness(55);
		bc = BlockClass.STONE;
		Item bd = new Item();
		bd.setID("cubyz:emerald");
		bd.setTexture("materials/emerald.png");
		setBlockDrop(bd);
	}
	
}