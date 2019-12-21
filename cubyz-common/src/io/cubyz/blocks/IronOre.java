package io.cubyz.blocks;

import io.cubyz.items.Item;
import io.cubyz.items.ItemBlock;

public class IronOre extends Ore {

	public IronOre() {
		setID("cubyz:iron_ore");
		height = 64;
		spawns = 20;
		maxLength = 3.5F;
		maxSize = 2.0F;
		setHardness(60);
		Item bd = new ItemBlock(this);
		bd.setID("cubyz:iron_ore");
		bd.setTexture("materials/iron_ore.png");
		setBlockDrop(bd);
	}
	
}