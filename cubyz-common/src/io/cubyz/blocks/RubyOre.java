package io.cubyz.blocks;

import io.cubyz.items.Item;

public class RubyOre extends Ore {

	public RubyOre() {
		setTexture("ruby_ore");
		setID("cubyz:ruby_ore");
		setHeight(8);
		setChance(0.006F);
		Item bd = new Item();
		bd.setID("cubyz_items:ruby");
		bd.setTexture("materials/ruby.png");
		setBlockDrop(bd);
	}
	
}