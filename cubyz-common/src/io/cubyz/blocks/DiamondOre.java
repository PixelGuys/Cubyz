package io.cubyz.blocks;

import io.cubyz.items.Item;

public class DiamondOre extends Ore {

	public DiamondOre() {
		setID("cubyz:diamond_ore");
		setHeight(15);
		setChance(0.002F);
		setHardness(80);
		bc = BlockClass.STONE;
		Item bd = new Item();
		bd.setID("cubyz:diamond");
		bd.setTexture("materials/diamond.png");
		setBlockDrop(bd);
	}
	
}