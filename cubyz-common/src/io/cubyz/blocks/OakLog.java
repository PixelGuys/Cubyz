package io.cubyz.blocks;

import io.cubyz.items.Item;

public class OakLog extends Block {

	public OakLog() {
		setTexture("oak_log");
		setID("cubyz:oak_log");
		Item bd = new Item();
		bd.setBlock(this);
		bd.setID("cubyz_items:oak_log");
		bd.setTexture("blocks/"+getTexture()+".png");
		setBlockDrop(bd);
	}
	
}