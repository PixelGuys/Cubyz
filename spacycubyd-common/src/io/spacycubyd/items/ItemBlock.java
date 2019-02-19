package io.spacycubyd.items;

import io.spacycubyd.blocks.Block;

public class ItemBlock extends Item {

	public ItemBlock(Block block) {
		this.fullTexturePath = "block/" + block.getTexture();
		this.itemDisplayName = block.getClass().getSimpleName();
	}
	
}
