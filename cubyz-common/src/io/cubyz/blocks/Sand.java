package io.cubyz.blocks;

import io.cubyz.items.Item;

public class Sand extends Block {

	public Sand() {
		setTexture("sand");
		setID("cubyz:sand");
		Item bd = new Item();
		bd.setBlock(this);
		bd.setTexture("blocks/"+getTexture()+".png");
		setBlockDrop(bd);
	}
	
}