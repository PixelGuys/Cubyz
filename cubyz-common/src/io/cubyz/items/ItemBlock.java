package io.cubyz.items;

import io.cubyz.blocks.Block;
import io.cubyz.translate.TextKey;

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
		this.setName(TextKey.createTextKey("block." + block.getRegistryID().getMod() + "." + block.getRegistryID().getID() + ".name"));
	}
	
}
