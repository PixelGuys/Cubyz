package io.cubyz.blocks;

import io.cubyz.items.Item;

public class WorkBench extends Block {
	public WorkBench() {
		setTexture("workbench");
		setID("cubyz:workbench");
		Item bd = new Item();
		bd.setBlock(this);
		bd.setID("cubyz_items:workbench");
		bd.setTexture("blocks/"+getTexture()+".png");
		setBlockDrop(bd);
		texConverted = true; // texture already in runtime format
		clickable = true; // Right will lead to opening the gui.
	}
}
