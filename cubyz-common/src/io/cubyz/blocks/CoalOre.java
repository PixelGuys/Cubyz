package io.cubyz.blocks;

import io.cubyz.items.Item;

public class CoalOre extends Ore {

	public CoalOre() {
		setTexture("coal_ore");
		setID("cubyz:coal_ore");
		setHeight(127);
		setChance(0.02F);
		Item bd = new Item();
		bd.setTexture("materials/coal.png");
		setBlockDrop(bd);
	}
	
}