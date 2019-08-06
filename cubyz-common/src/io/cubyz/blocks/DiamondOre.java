package io.cubyz.blocks;

import io.cubyz.items.Item;

public class DiamondOre extends Ore {

	public DiamondOre() {
		setTexture("diamond_ore");
		setID("cubyz:diamond_ore");
		setHeight(15);
		setChance(0.002F);
		Item bd = new Item();
		bd.setID("cubyz_items:diamond");
		bd.setTexture("materials/diamond.png");
		setBlockDrop(bd);
	}
	
}