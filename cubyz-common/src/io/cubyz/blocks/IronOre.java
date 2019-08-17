package io.cubyz.blocks;

import io.cubyz.items.Item;

public class IronOre extends Ore {

	public IronOre() {
		setID("cubyz:iron_ore");
		setHeight(63);
		setChance(0.03F);
		Item bd = new Item();
		bd.setBlock(this);
		bd.setID("cubyz:iron_ore");
		bd.setTexture("materials/iron_ore.png");
		setBlockDrop(bd);
	}
	
}