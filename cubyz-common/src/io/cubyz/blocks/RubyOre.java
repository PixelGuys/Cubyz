package io.cubyz.blocks;

import io.cubyz.items.Item;

public class RubyOre extends Ore {

	public RubyOre() {
		setID("cubyz:ruby_ore");
		height = 8;
		spawns = 1;
		maxLength = 4;
		maxSize = 1.0F;
		setHardness(50);
		Item bd = new Item();
		bd.setID("cubyz:ruby");
		bd.setTexture("materials/ruby.png");
		setBlockDrop(bd);
	}
	
}