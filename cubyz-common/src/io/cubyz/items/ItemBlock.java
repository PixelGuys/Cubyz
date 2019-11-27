package io.cubyz.items;

import io.cubyz.blocks.Block;

public class ItemBlock extends Item {

	private Block block;
	
	public ItemBlock() {
		
	}
	
	public ItemBlock(Block block) {
		setBlock(block);
	}
	
	public Block getBlock() {
		return block;
	}
	
	public void setBlock(Block block) {
		this.block = block;
		setID(block.getRegistryID());
		texturePath = "blocks/" + block.getRegistryID().getID() + ".png"; // not reliable
	}
	
}
