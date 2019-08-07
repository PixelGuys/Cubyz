package io.cubyz.blocks;

import io.cubyz.items.Item;

public class OakPlanks extends Block {
	
	public OakPlanks() {
		setTexture("oak_planks");
		setID("cubyz:oak_planks");
		Item bd = new Item();
		bd.setBlock(this);
		bd.setID("cubyz_items:oak_planks");
		bd.setTexture("blocks/"+getTexture()+".png");
		setBlockDrop(bd);
	}

}
