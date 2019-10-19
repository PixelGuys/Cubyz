package io.cubyz.blocks;

import io.cubyz.items.Item;

public class CoalOre extends Ore {

	public CoalOre() {
		setID("cubyz:coal_ore");
		setHeight(127);
		setChance(0.02F);
		setHardness(40);
		bc = BlockClass.STONE;
		Item bd = new Item();
		bd.setID("cubyz:coal");
		bd.setTexture("materials/coal.png");
		setBlockDrop(bd);
	}
	
}