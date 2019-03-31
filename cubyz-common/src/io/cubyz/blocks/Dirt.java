package io.cubyz.blocks;

import io.cubyz.items.Item;

public class Dirt extends Block {

	public Dirt() {
		setTexture("dirt");
		setID("cubyz:dirt");
		Item bd = new Item();
		bd.setBlock(this);
		bd.setTexture("blocks/"+getTexture()+".png");
		setBlockDrop(bd);
	}
	
}