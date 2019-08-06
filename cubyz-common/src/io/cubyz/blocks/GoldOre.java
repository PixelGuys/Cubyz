package io.cubyz.blocks;

import io.cubyz.items.Item;

public class GoldOre extends Ore {

	public GoldOre() {
		setTexture("gold_ore");
		setID("cubyz:gold_ore");
		setHeight(32);
		setChance(0.005F);
		Item bd = new Item();
		bd.setID("cubyz_items:gold_ore");
		bd.setTexture("materials/gold_ore.png");
		setBlockDrop(bd);
	}
	
}