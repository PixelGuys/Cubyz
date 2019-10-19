package io.cubyz.blocks;

import io.cubyz.items.Item;

public class GoldOre extends Ore {

	public GoldOre() {
		setID("cubyz:gold_ore");
		setHeight(32);
		setChance(0.005F);
		setHardness(45);
		bc = BlockClass.STONE;
		Item bd = new Item();
		bd.setID("cubyz:gold_ore");
		bd.setTexture("materials/gold_ore.png");
		setBlockDrop(bd);
	}
	
}