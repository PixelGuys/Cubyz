package io.cubyz.blocks;

import io.cubyz.items.Item;

public class Cactus extends Block {
	
	public Cactus() {
		setTexture("cactus");
		setID("cubyz:cactus");
		Item bd = new Item();
		bd.setBlock(this);
		bd.setID("cubyz_items:cactus");
		bd.setTexture("blocks/"+getTexture()+".png");
		setBlockDrop(bd);
	}
	
}
